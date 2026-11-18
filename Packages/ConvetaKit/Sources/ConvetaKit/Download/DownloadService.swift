import Foundation
import os

/// Downloads a link and delivers it in the format the person chose. The download lands in a hidden
/// working folder; when it already plays everywhere in the chosen format it is moved into place,
/// otherwise ``ConversionService`` converts it (a 4K YouTube video in VP9 becomes HEVC so QuickTime
/// plays it; a TikTok can become a GIF, a talk an MP3).
public struct DownloadService: Sendable {
    public let engine: DownloadEngine
    public let conversion: ConversionService

    public init(engine: DownloadEngine, conversion: ConversionService) {
        self.engine = engine
        self.conversion = conversion
    }

    /// - Parameter nameSuffix: added to the title, e.g. " (1080p)" when several sizes of one video are saved.
    public func download(_ media: RemoteMedia, settings: ConversionSettings, into directory: URL, nameSuffix: String = "",
                         progress: @escaping ProgressHandler = { _ in }) async throws -> URL {
        let workspace = directory.appending(path: ".conveta-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        } catch {
            throw ConversionError.noWriteAccess(directory)
        }
        defer { try? FileManager.default.removeItem(at: workspace) }

        let format = settings.format
        let container = Self.container(for: format, hasVideo: media.hasVideo)
        let height = settings.downloadHeight ?? (settings.video.resolution == .original ? nil : settings.video.resolution.rawValue)
        // Above 1080p sites rarely offer H.264, so expect to convert and leave room for it on the bar.
        let likelyConversion = !Self.keepsAsIs(format) || (container == .mp4 && (height ?? 2160) > 1080)
        let relay = ProgressRelay(progress)
        let downloadShare = likelyConversion ? 0.6 : 0.97

        let downloaded = try await engine.download(media, container: container, maxHeight: height, subtitles: settings.subtitles,
                                                   into: workspace) { value in
            relay.report(value * downloadShare)
        }
        try Task.checkCancellation()

        let baseName = media.fileBaseName + nameSuffix
        let named = workspace.appending(path: baseName).appendingPathExtension(downloaded.pathExtension)
        try FileManager.default.moveItem(at: downloaded, to: named)
        let info = try await MediaProbe.probe(named, tools: conversion.tools)

        let output: URL
        if Self.isReady(info, downloadedAs: named.pathExtension, for: settings) {
            relay.report(1)
            output = try OutputNaming.moveIntoPlace(named, in: directory, baseName: baseName, pathExtension: named.pathExtension)
        } else {
            let conversionSettings = Self.conversionSettings(for: settings, info: info)
            let start = relay.current
            output = try await conversion.convert(named, info: info, settings: conversionSettings, into: directory) { value in
                relay.report(start + value * (1 - start))
            }
        }
        try Self.placeSubtitleFiles(from: workspace, next: output)
        return output
    }

    /// Subtitle files yt-dlp wrote ("download.en.srt") move beside the result as "Title.en.srt".
    static func placeSubtitleFiles(from workspace: URL, next output: URL) throws {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? []
        let base = output.deletingPathExtension().lastPathComponent
        for file in files where ["srt", "vtt", "ass"].contains(file.pathExtension.lowercased()) {
            // "download.en-US.srt" → language "en-US"
            let parts = file.deletingPathExtension().lastPathComponent.split(separator: ".")
            let language = parts.count > 1 ? String(parts.last!) : "subtitles"
            _ = try OutputNaming.moveIntoPlace(file, in: output.deletingLastPathComponent(),
                                               baseName: "\(base).\(language)", pathExtension: file.pathExtension)
        }
    }

    static func container(for format: OutputFormat, hasVideo: Bool) -> DownloadEngine.Container {
        guard hasVideo, format.kind != .audio else { return .audio }
        switch format {
        case .webm: return .webm
        case .mkv: return .mkv
        default: return .mp4
        }
    }

    /// Formats a download can be delivered in without re-encoding, when the codecs allow.
    static func keepsAsIs(_ format: OutputFormat) -> Bool {
        [.mp4, .webm, .mkv, .m4a].contains(format)
    }

    /// Whether the downloaded file can be used as is. MP4 must play on every Apple device (H.264 or
    /// HEVC with AAC) unless the person asked for no re-encoding; WebM and MKV are kept as served.
    static func isReady(_ info: MediaInfo, downloadedAs ext: String, for settings: ConversionSettings) -> Bool {
        let ext = ext.lowercased()
        switch settings.format {
        case .mp4:
            let untouched = settings.video.frameRate == .original && settings.video.includeAudio
                && (settings.video.codec == .h264 || settings.video.codec == .passthrough || settings.video.codec == .hevc)
            return ext == "mp4" && untouched && info.playsEverywhereOnApple
        case .webm: return ext == "webm" && settings.video.includeAudio && settings.video.frameRate == .original
        case .mkv: return ext == "mkv" && settings.video.includeAudio && settings.video.frameRate == .original
        case .m4a: return ext == "m4a" && settings.audio.codec == .aac
        default: return false
        }
    }

    /// Settings for converting a download: the size is already right; pictures taller than 1080p
    /// become HEVC (H.264 struggles above it), and quality stays high so nothing is lost twice.
    static func conversionSettings(for settings: ConversionSettings, info: MediaInfo) -> ConversionSettings {
        var result = settings
        result.video.resolution = .original
        if [.mp4, .mov, .m4v, .mkv].contains(settings.format) {
            let tall = (info.pixelSize.map { min($0.width, $0.height) } ?? 0) > 1080
            if result.video.codec == .passthrough || (tall && result.video.codec == .h264) {
                result.video.codec = tall ? .hevc : .h264
            }
            if result.video.quality == .compact || result.video.quality == .balanced { result.video.quality = .high }
        }
        return result
    }
}

/// Keeps a progress bar moving forward across the download and the conversion that may follow.
final class ProgressRelay: Sendable {
    private let handler: ProgressHandler
    private let last = OSAllocatedUnfairLock(initialState: 0.0)

    init(_ handler: @escaping ProgressHandler) { self.handler = handler }

    var current: Double { last.withLock { $0 } }

    func report(_ value: Double) {
        let next = last.withLock { last -> Double? in
            guard value > last else { return nil }
            last = value
            return value
        }
        if let next { handler(next) }
    }
}
