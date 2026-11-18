import CryptoKit
import Foundation

public enum DownloadError: LocalizedError, Equatable {
    case engineMissing
    case engineDownloadFailed(String)
    case checksumMismatch
    case playlist
    case unsupportedLink
    case loginRequired(site: String)
    case unavailable(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .engineMissing: "The downloader isn’t installed yet."
        case .engineDownloadFailed(let reason): "The downloader couldn’t be installed: \(reason)"
        case .checksumMismatch: "The downloaded engine didn’t match its published checksum, so it wasn’t installed."
        case .playlist: "This is a playlist. Paste a link to a single video."
        case .unsupportedLink: "There’s no video Conveta can download at this link."
        case .loginRequired(let site): "\(site) needs you to be signed in for this video. Turn on browser cookies in Settings → Downloads."
        case .unavailable(let reason): reason
        case .failed(let reason): reason
        }
    }
}

/// yt-dlp, the open-source engine behind downloads. It is fetched on first use from its official
/// GitHub release and verified against the release's SHA-256 list, then kept up to date, because
/// websites change often and an old engine stops working.
public struct DownloadEngine: Sendable {
    public let executable: URL
    public let ffmpegFolder: URL?
    /// A browser to borrow cookies from, for posts that need a signed-in account ("safari", "chrome"...).
    public var cookiesBrowser: String?

    public init(executable: URL, ffmpegFolder: URL?, cookiesBrowser: String? = nil) {
        self.executable = executable
        self.ffmpegFolder = ffmpegFolder
        self.cookiesBrowser = cookiesBrowser
    }

    public var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    public func version() async -> String? {
        guard isInstalled else { return nil }
        return try? await ToolRunner.run(executable, ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Install and update

    static let releaseBase = URL(string: "https://github.com/yt-dlp/yt-dlp/releases")!

    /// The newest release's version, read from where GitHub's "latest" link redirects.
    public static func latestVersion(session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: releaseBase.appending(path: "latest"))
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let final = response.url, final.path.contains("/tag/") else {
            throw DownloadError.engineDownloadFailed("GitHub didn’t say which version is newest.")
        }
        return final.lastPathComponent
    }

    /// Downloads the newest engine, checks its SHA-256 against the release, and installs it atomically.
    public func install(session: URLSession = .shared) async throws {
        let latest = Self.releaseBase.appending(path: "latest/download")
        let sums: String
        do {
            let (data, response) = try await session.data(from: latest.appending(path: "SHA2-256SUMS"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            sums = String(decoding: data, as: UTF8.self)
        } catch {
            throw DownloadError.engineDownloadFailed(error.localizedDescription)
        }
        guard let expected = Self.checksum(for: "yt-dlp_macos", in: sums) else {
            throw DownloadError.engineDownloadFailed("The release has no macOS build.")
        }

        let temporary: URL
        do {
            let (file, response) = try await session.download(from: latest.appending(path: "yt-dlp_macos"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            temporary = file
        } catch {
            throw DownloadError.engineDownloadFailed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.verify(temporary, sha256: expected)
        try Self.place(temporary, at: executable)
    }

    static func checksum(for name: String, in sums: String) -> String? {
        sums.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[1] == name, parts[0].count == 64 else { return nil }
            return String(parts[0]).lowercased()
        }.first
    }

    static func verify(_ file: URL, sha256 expected: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw DownloadError.checksumMismatch }
    }

    static func place(_ file: URL, at destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent)-\(UUID().uuidString)")
        try manager.copyItem(at: file, to: staging)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        _ = try manager.replaceItemAt(destination, withItemAt: staging)
    }

    // MARK: Reading a link

    var commonArguments: [String] {
        var args = ["--no-playlist", "--no-warnings", "--ignore-config", "--no-cache-dir"]
        if let ffmpegFolder { args += ["--ffmpeg-location", ffmpegFolder.path] }
        if let cookiesBrowser { args += ["--cookies-from-browser", cookiesBrowser] }
        return args
    }

    /// Reads title, length and thumbnail for a link without downloading it.
    public func inspect(_ link: URL) async throws -> RemoteMedia {
        guard isInstalled else { throw DownloadError.engineMissing }
        let json: String
        do {
            json = try await ToolRunner.run(executable, commonArguments + ["--dump-single-json", "--flat-playlist", link.absoluteString])
        } catch let failure as ToolRunner.Failure {
            throw Self.explain(failure.message, link: link)
        }
        return try Self.media(from: Data(json.utf8), link: link)
    }

    static func media(from json: Data, link: URL) throws -> RemoteMedia {
        guard let report = try? JSONDecoder().decode(Report.self, from: json) else { throw DownloadError.unsupportedLink }
        if report.type == "playlist" { throw DownloadError.playlist }
        let page = report.webpageURL.flatMap(URL.init(string:)) ?? link
        let hasVideo = (report.vcodec.map { $0 != "none" } ?? true) && (report.width != nil || report.height != nil || report.vcodec != nil)
        return RemoteMedia(
            link: link, pageURL: page, id: report.id ?? UUID().uuidString,
            title: report.title ?? "Download", uploader: report.uploader ?? report.channel,
            duration: report.duration, thumbnail: report.thumbnail.flatMap(URL.init(string:)),
            site: LinkDetector.siteName(extractor: report.extractorKey, url: page),
            hasVideo: hasVideo, width: report.width, height: report.height
        )
    }

    struct Report: Decodable {
        var type: String?
        var id: String?
        var title: String?
        var uploader: String?
        var channel: String?
        var duration: Double?
        var thumbnail: String?
        var webpageURL: String?
        var extractorKey: String?
        var vcodec: String?
        var width: Int?
        var height: Int?

        enum CodingKeys: String, CodingKey {
            case type = "_type", id, title, uploader, channel, duration, thumbnail, vcodec, width, height
            case webpageURL = "webpage_url", extractorKey = "extractor_key"
        }
    }

    // MARK: Downloading

    /// Downloads `media` into `folder` and returns the file. Video comes as MP4 with H.264 and AAC
    /// when the site offers it (so it usually needs no conversion), never taller than `maxHeight`.
    public func download(_ media: RemoteMedia, audioOnly: Bool, maxHeight: Int?, into folder: URL,
                         progress: @escaping ProgressHandler) async throws -> URL {
        guard isInstalled else { throw DownloadError.engineMissing }
        let args = commonArguments + Self.downloadArguments(audioOnly: audioOnly, maxHeight: maxHeight, folder: folder) + [media.pageURL.absoluteString]
        let tracker = DownloadProgress(parts: audioOnly ? 1 : 2, handler: progress)
        let output: String
        do {
            output = try await ToolRunner.run(executable, args) { line in tracker.consume(line) }
        } catch let failure as ToolRunner.Failure {
            throw Self.explain(failure.message, link: media.link)
        }
        let path = output.split(whereSeparator: \.isNewline).last { $0.hasPrefix("conveta-file ") }.map { String($0.dropFirst(13)) }
        guard let path, FileManager.default.fileExists(atPath: path) else {
            throw DownloadError.failed("The download finished but no file was written.")
        }
        return URL(filePath: path)
    }

    static func downloadArguments(audioOnly: Bool, maxHeight: Int?, folder: URL) -> [String] {
        var args = [
            "--newline", "--no-mtime", "--no-part", "-P", folder.path, "-o", "download.%(ext)s",
            "--progress-template", "download:conveta-progress %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            "--print", "after_move:conveta-file %(filepath)s",
            // --print alone would only simulate and silence progress.
            "--no-simulate", "--progress",
        ]
        if audioOnly {
            args += ["-f", "ba/b", "-S", "acodec:aac"]
        } else {
            let resolution = maxHeight.map { "res:\($0)" } ?? "res"
            args += ["-f", "bv*+ba/b", "-S", "\(resolution),vcodec:h264,acodec:aac", "--merge-output-format", "mp4"]
        }
        return args
    }

    /// Turns yt-dlp's last error line into a sentence.
    static func explain(_ message: String, link: URL) -> DownloadError {
        let lower = message.lowercased()
        let site = LinkDetector.knownSite(for: link) ?? link.host() ?? "This site"
        if lower.contains("unsupported url") { return .unsupportedLink }
        if lower.contains("sign in") || lower.contains("login") || lower.contains("log in") || lower.contains("cookies") || lower.contains("private") {
            return .loginRequired(site: site)
        }
        if lower.contains("video unavailable") || lower.contains("removed") || lower.contains("not available") {
            return .unavailable("This video isn’t available. It may have been removed or blocked in your region.")
        }
        if lower.contains("unable to download") || lower.contains("urlopen error") || lower.contains("timed out") {
            return .failed("\(site) couldn’t be reached. Check your connection and try again.")
        }
        let cleaned = message.replacingOccurrences(of: "ERROR: ", with: "")
        return .failed("The download failed: \(cleaned)")
    }
}

/// Folds yt-dlp's per-file progress into one value. A video is usually two files (picture, then
/// sound) that are downloaded one after the other.
final class DownloadProgress: Sendable {
    private let parts: Int
    private let throttle: ProgressThrottle
    private let state = OSAllocatedUnfairLock(initialState: (part: 0, last: 0.0))

    init(parts: Int, handler: @escaping ProgressHandler) {
        self.parts = max(1, parts)
        throttle = ProgressThrottle(handler)
    }

    func consume(_ line: String) {
        guard let fraction = Self.fraction(line) else { return }
        let overall = state.withLock { state -> Double in
            // A sharp drop means the next file started.
            if fraction < state.last - 0.5, state.part < parts - 1 { state.part += 1 }
            state.last = fraction
            return (Double(state.part) + fraction) / Double(parts)
        }
        throttle.report(overall * 0.98)
    }

    /// "conveta-progress 1024 4096 NA" → 0.25
    static func fraction(_ line: String) -> Double? {
        let parts = line.split(separator: " ")
        guard parts.count == 4, parts[0] == "conveta-progress", let done = Double(parts[1]) else { return nil }
        let total = Double(parts[2]) ?? Double(parts[3]) ?? 0
        guard total > 0 else { return nil }
        return min(1, done / total)
    }
}

import os
