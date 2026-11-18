import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Reads files Apple's frameworks can't open (MKV, WebM, FLV, WMA, Ogg Vorbis, APE...) with `ffprobe`.
enum FFprobe {
    static func probe(_ url: URL, tools: FFmpegTools, type: UTType, size: Int64) async throws -> MediaInfo {
        let json: String
        do {
            json = try await ToolRunner.run(tools.ffprobe, [
                "-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path,
            ])
        } catch is ToolRunner.Failure {
            throw ProbeError.unreadable(url.lastPathComponent)
        }
        guard let report = try? JSONDecoder().decode(Report.self, from: Data(json.utf8)) else {
            throw ProbeError.unreadable(url.lastPathComponent)
        }
        return try info(from: report, url: url, type: type, size: size)
    }

    static func info(from report: Report, url: URL, type: UTType, size: Int64) throws -> MediaInfo {
        // Cover art in audio files is a "video" stream marked as an attached picture; it doesn't count.
        let video = report.streams.first { $0.codecType == "video" && $0.disposition?.attachedPic != 1 }
        let audio = report.streams.first { $0.codecType == "audio" }
        guard video != nil || audio != nil else { throw ProbeError.unreadable(url.lastPathComponent) }

        var info = MediaInfo(kind: video == nil ? .audio : .video, contentType: type, fileSize: size)
        info.readableByApple = false
        info.hasAudio = audio != nil
        info.duration = report.format?.duration.flatMap(Double.init) ?? (video ?? audio)?.duration.flatMap(Double.init)
        if let rate = audio?.bitRate.flatMap(Double.init), rate > 0 { info.audioBitrate = Int((rate / 1000).rounded()) }
        if video != nil, let audio { info.audioCodec = audio.codecName.map(Self.codecName) }
        if let video {
            var width = video.width ?? 0, height = video.height ?? 0
            if let rotation = video.rotation, abs(rotation) % 180 == 90 { swap(&width, &height) }
            info.pixelSize = CGSize(width: width, height: height)
            info.frameRate = video.averageFrameRate.flatMap(Self.rate)
            info.codec = video.codecName.map(Self.codecName)
        } else if let audio {
            info.codec = audio.codecName.map(Self.codecName)
            info.sampleRate = audio.sampleRate.flatMap(Double.init)
            info.channels = audio.channels
        }
        return info
    }

    /// "30000/1001" → 29.97
    static func rate(_ fraction: String) -> Double? {
        let parts = fraction.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return Double(fraction) }
        let value = parts[0] / parts[1]
        return value > 0 ? value : nil
    }

    static func codecName(_ name: String) -> String {
        let names = [
            "h264": "H.264", "hevc": "HEVC", "vp9": "VP9", "vp8": "VP8", "av1": "AV1", "mpeg4": "MPEG-4",
            "mpeg2video": "MPEG-2", "wmv2": "WMV", "wmv3": "WMV", "vc1": "VC-1", "flv1": "Sorenson", "prores": "ProRes",
            "mp3": "MP3", "aac": "AAC", "opus": "Opus", "vorbis": "Vorbis", "flac": "FLAC", "alac": "Apple Lossless",
            "wmav2": "WMA", "wmapro": "WMA Pro", "ape": "APE", "wavpack": "WavPack", "ac3": "AC-3", "eac3": "E-AC-3",
            "dts": "DTS", "amr_nb": "AMR", "amr_wb": "AMR-WB", "truehd": "TrueHD",
        ]
        if let known = names[name] { return known }
        return name.hasPrefix("pcm_") ? "PCM" : name.uppercased()
    }

    struct Report: Decodable {
        var streams: [Stream] = []
        var format: Format?
    }

    struct Stream: Decodable {
        var codecType: String?
        var codecName: String?
        var width: Int?
        var height: Int?
        var averageFrameRate: String?
        var sampleRate: String?
        var channels: Int?
        var duration: String?
        var bitRate: String?
        var disposition: Disposition?
        var sideDataList: [SideData]?

        var rotation: Int? { sideDataList?.compactMap(\.rotation).first }

        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type", codecName = "codec_name", width, height
            case averageFrameRate = "avg_frame_rate", sampleRate = "sample_rate", channels, duration, disposition
            case bitRate = "bit_rate"
            case sideDataList = "side_data_list"
        }
    }

    struct SideData: Decodable {
        var rotation: Int?
    }

    struct Disposition: Decodable {
        var attachedPic: Int?
        enum CodingKeys: String, CodingKey { case attachedPic = "attached_pic" }
    }

    struct Format: Decodable {
        var duration: String?
    }
}
