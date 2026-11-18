import Foundation

/// Downloads a link and delivers it in the format the person chose. The download lands in a hidden
/// working folder; when it is already in the right format it is moved into place, otherwise
/// ``ConversionService`` converts it (so a TikTok can become a GIF, a YouTube video an MP3).
public struct DownloadService: Sendable {
    public let engine: DownloadEngine
    public let conversion: ConversionService

    public init(engine: DownloadEngine, conversion: ConversionService) {
        self.engine = engine
        self.conversion = conversion
    }

    public func download(_ media: RemoteMedia, settings: ConversionSettings, into directory: URL,
                         progress: @escaping ProgressHandler = { _ in }) async throws -> URL {
        let workspace = directory.appending(path: ".conveta-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        } catch {
            throw ConversionError.noWriteAccess(directory)
        }
        defer { try? FileManager.default.removeItem(at: workspace) }

        let format = settings.format
        let audioOnly = format.kind == .audio || !media.hasVideo
        let maxHeight = settings.video.resolution == .original ? nil : settings.video.resolution.rawValue
        let needsConversion = !Self.isReady(downloadedAs: audioOnly ? "m4a" : "mp4", for: settings)
        let share = needsConversion ? 0.75 : 1.0

        let downloaded = try await engine.download(media, audioOnly: audioOnly, maxHeight: maxHeight, into: workspace) { value in
            progress(value * share)
        }
        try Task.checkCancellation()

        // Name the file after the title, so the conversion and the final file carry it.
        let named = workspace.appending(path: media.fileBaseName).appendingPathExtension(downloaded.pathExtension)
        try FileManager.default.moveItem(at: downloaded, to: named)

        if !needsConversion, named.pathExtension.lowercased() == format.fileExtension {
            return try OutputNaming.moveIntoPlace(named, in: directory, baseName: media.fileBaseName, pathExtension: named.pathExtension)
        }
        var settings = settings
        settings.video.resolution = .original  // the download already respects the size limit
        let info = try await MediaProbe.probe(named, tools: conversion.tools)
        return try await conversion.convert(named, info: info, settings: settings, into: directory) { value in
            progress(share + value * (1 - share))
        }
    }

    /// Whether the file yt-dlp delivers can be used as is: an MP4 (H.264 + AAC) for MP4 at any quality
    /// short of re-encoding choices, or an M4A for AAC-in-M4A.
    static func isReady(downloadedAs ext: String, for settings: ConversionSettings) -> Bool {
        switch settings.format {
        case .mp4: ext == "mp4" && settings.video.frameRate == .original && settings.video.includeAudio
            && (settings.video.codec == .h264 || settings.video.codec == .passthrough)
        case .m4a: ext == "m4a" && settings.audio.codec == .aac
        default: false
        }
    }
}
