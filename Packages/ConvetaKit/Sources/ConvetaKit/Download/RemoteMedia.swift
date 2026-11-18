import Foundation

/// A video or song on a website, as yt-dlp describes it before downloading.
public struct RemoteMedia: Sendable, Hashable, Codable {
    /// The link the person pasted.
    public var link: URL
    /// The canonical page, used for the download.
    public var pageURL: URL
    public var id: String
    public var title: String
    public var uploader: String?
    public var duration: Double?
    public var thumbnail: URL?
    /// The website, for example "YouTube" or "TikTok".
    public var site: String
    public var hasVideo: Bool
    public var width: Int?
    public var height: Int?

    /// "YouTube · Channel Name · 3:12"
    public var details: String {
        var parts = [site]
        if let uploader, !uploader.isEmpty { parts.append(uploader) }
        if let duration, duration > 0 { parts.append(MediaInfo.formatDuration(duration)) }
        if let height, hasVideo { parts.append("up to \(height)p") }
        return parts.joined(separator: " · ")
    }

    /// The kind of file it becomes: video unless the site only has sound.
    public var kind: MediaKind { hasVideo ? .video : .audio }

    /// A file name made from the title: no slashes or colons, no leading dots, at most 120 characters.
    public var fileBaseName: String {
        let forbidden = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters).union(.newlines)
        var name = title.components(separatedBy: forbidden).joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        if name.count > 120 { name = String(name.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "\(site) \(id)" : name
    }

    /// Facts for planning a conversion, before the file exists.
    public var plannedInfo: MediaInfo {
        var info = MediaInfo(kind: kind, contentType: .movie, fileSize: 0)
        info.duration = duration
        if let width, let height { info.pixelSize = CGSize(width: width, height: height) }
        info.hasAudio = true
        return info
    }
}

/// Recognises links Conveta should treat as downloads.
public enum LinkDetector {
    private static let knownSites: [(hosts: [String], name: String)] = [
        (["youtube.com", "youtu.be", "youtube-nocookie.com"], "YouTube"),
        (["instagram.com"], "Instagram"),
        (["tiktok.com"], "TikTok"),
        (["x.com", "twitter.com"], "X"),
        (["facebook.com", "fb.watch"], "Facebook"),
        (["vimeo.com"], "Vimeo"),
        (["reddit.com", "redd.it"], "Reddit"),
        (["soundcloud.com"], "SoundCloud"),
        (["twitch.tv"], "Twitch"),
        (["dailymotion.com"], "Dailymotion"),
        (["threads.net", "threads.com"], "Threads"),
        (["bsky.app"], "Bluesky"),
        (["pinterest.com", "pin.it"], "Pinterest"),
    ]

    /// Links found in pasted text: one per line or separated by spaces, http(s) only.
    public static func links(in text: String) -> [URL] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .compactMap { word -> URL? in
                let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(),"))
                guard let url = URL(string: trimmed), isWebLink(url) else { return nil }
                return url
            }
    }

    public static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), host.contains(".") else { return false }
        return true
    }

    /// The site's name for a link to a site Conveta knows, else `nil` (yt-dlp may still support it).
    public static func knownSite(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        return knownSites.first { site in site.hosts.contains { host == $0 || host.hasSuffix("." + $0) } }?.name
    }

    /// Turns yt-dlp's extractor key ("Youtube", "TikTok", "Twitter") into a display name.
    static func siteName(extractor: String?, url: URL) -> String {
        if let known = knownSite(for: url) { return known }
        let names = ["Youtube": "YouTube", "Twitter": "X", "Generic": url.host() ?? "Web"]
        guard let extractor else { return url.host() ?? "Web" }
        return names[extractor] ?? extractor
    }
}
