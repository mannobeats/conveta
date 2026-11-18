import Foundation

/// What a link points to: one video, or a list of them (a playlist, a channel's videos).
public enum LinkContents: Sendable, Equatable {
    case single(RemoteMedia)
    case playlist(Playlist)
}

/// A playlist or channel, read without visiting each video (yt-dlp's "flat" listing).
public struct Playlist: Sendable, Hashable {
    public var link: URL
    public var title: String
    public var uploader: String?
    public var site: String
    public var entries: [RemoteMedia]

    /// Total length of the entries whose length is known.
    public var totalDuration: Double {
        entries.compactMap(\.duration).reduce(0, +)
    }
}

/// Subtitles for downloads.
public struct SubtitleOptions: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable, CaseIterable, Identifiable {
        case off, embed, file
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .off: "Off"
            case .embed: "In the Video"
            case .file: "Separate File (.srt)"
            }
        }
    }

    public var mode: Mode = .off
    /// A language code such as "en" or "fr"; regional variants ("en-US") are included.
    public var language = Locale.current.language.languageCode?.identifier ?? "en"
    /// Also use captions the site generated automatically when there are none written by people.
    public var includeAutomatic = true

    public init() {}

    var arguments: [String] {
        guard mode != .off else { return [] }
        var args = ["--write-subs", "--sub-langs", "\(language).*,\(language)"]
        if includeAutomatic { args.append("--write-auto-subs") }
        switch mode {
        case .embed: args.append("--embed-subs")
        case .file: args += ["--convert-subs", "srt"]
        case .off: break
        }
        return args
    }
}

extension DownloadEngine {
    /// Reads a link: one video, or the list behind a playlist or channel link.
    public func read(_ link: URL) async throws -> LinkContents {
        guard isInstalled else { throw DownloadError.engineMissing }
        let json = try await readJSON(Self.channelVideos(link), playlist: Self.isPlaylistLink(link))
        if let playlist = try Self.playlist(from: json, link: link) {
            // A channel lists its tabs (Videos, Shorts...) rather than videos; open the first tab.
            if playlist.entries.isEmpty, let tab = Self.firstTab(in: json) {
                let tabJSON = try await readJSON(tab, playlist: true)
                if let inner = try Self.playlist(from: tabJSON, link: link) {
                    return .playlist(Playlist(link: link, title: playlist.title, uploader: playlist.uploader ?? inner.uploader,
                                              site: playlist.site, entries: inner.entries))
                }
            }
            return .playlist(playlist)
        }
        return .single(try Self.media(from: json, link: link))
    }

    private func readJSON(_ link: URL, playlist: Bool) async throws -> Data {
        var args = commonArguments
        if playlist { args.removeAll { $0 == "--no-playlist" }; args += ["--yes-playlist", "--playlist-end", "\(Self.playlistLimit)"] }
        do {
            let json = try await ToolRunner.run(executable, args + ["--dump-single-json", "--flat-playlist", link.absoluteString])
            return Data(json.utf8)
        } catch let failure as ToolRunner.Failure {
            throw Self.explain(failure.message, link: link)
        }
    }

    /// A YouTube channel's home lists its tabs (Videos, Live, Shorts), not videos; go to Videos.
    static func channelVideos(_ url: URL) -> URL {
        guard LinkDetector.knownSite(for: url) == "YouTube" else { return url }
        let parts = url.path().split(separator: "/")
        let isChannel = parts.first.map { $0.hasPrefix("@") } == true && parts.count == 1
            || (["channel", "c", "user"].contains(parts.first.map(String.init) ?? "") && parts.count == 2)
        return isChannel ? url.appending(path: "videos") : url
    }

    /// Lists longer than this are cut; nobody ticks through more in one go.
    public static let playlistLimit = 1000

    /// Links that are lists by nature. A video link that also names a list (watch?v=…&list=…) stays one video.
    public static func isPlaylistLink(_ url: URL) -> Bool {
        let path = url.path().lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let hasList = query.contains { $0.name == "list" }
        let hasVideo = query.contains { $0.name == "v" }
        if hasList && !hasVideo { return true }
        guard LinkDetector.knownSite(for: url) == "YouTube" else { return path.contains("/playlist") || path.contains("/sets/") }
        return path.hasPrefix("/@") || path.hasPrefix("/channel/") || path.hasPrefix("/c/") || path.hasPrefix("/user/") || path.hasPrefix("/playlist")
    }

    static func playlist(from json: Data, link: URL) throws -> Playlist? {
        guard let report = try? JSONDecoder().decode(ListReport.self, from: json), report.type == "playlist" else { return nil }
        let site = LinkDetector.siteName(extractor: report.extractorKey, url: link)
        let entries = (report.entries ?? []).compactMap { entry -> RemoteMedia? in
            guard entry.type != "playlist", !(entry.ieKey ?? "").hasSuffix("Tab"),
                  let url = (entry.url ?? entry.webpageURL).flatMap(URL.init(string:)), LinkDetector.isWebLink(url) else { return nil }
            let thumbnail = entry.thumbnails?.last?.url.flatMap(URL.init(string:))
            return RemoteMedia(link: url, pageURL: url, id: entry.id ?? url.absoluteString, title: entry.title ?? url.absoluteString,
                               uploader: entry.uploader ?? entry.channel ?? report.uploader ?? report.channel,
                               duration: entry.duration, thumbnail: thumbnail, site: site, hasVideo: true, width: nil, height: nil)
        }
        return Playlist(link: link, title: report.title ?? "Playlist", uploader: report.uploader ?? report.channel, site: site, entries: entries)
    }

    static func firstTab(in json: Data) -> URL? {
        guard let report = try? JSONDecoder().decode(ListReport.self, from: json) else { return nil }
        let tabs = (report.entries ?? []).filter { $0.type == "playlist" || ($0.ieKey ?? "").hasSuffix("Tab") || ($0.type == "url" && ($0.url ?? "").contains("/videos")) }
        let preferred = tabs.first { ($0.url ?? "").hasSuffix("/videos") } ?? tabs.first
        return preferred?.url.flatMap(URL.init(string:))
    }

    struct ListReport: Decodable {
        var type: String?
        var title: String?
        var uploader: String?
        var channel: String?
        var extractorKey: String?
        var entries: [Entry]?

        enum CodingKeys: String, CodingKey {
            case type = "_type", title, uploader, channel, entries
            case extractorKey = "extractor_key"
        }

        struct Entry: Decodable {
            var type: String?
            var ieKey: String?
            var id: String?
            var url: String?
            var webpageURL: String?
            var title: String?
            var uploader: String?
            var channel: String?
            var duration: Double?
            var thumbnails: [Thumbnail]?

            enum CodingKeys: String, CodingKey {
                case type = "_type", ieKey = "ie_key", id, url, title, uploader, channel, duration, thumbnails
                case webpageURL = "webpage_url"
            }
        }

        struct Thumbnail: Decodable { var url: String? }
    }
}
