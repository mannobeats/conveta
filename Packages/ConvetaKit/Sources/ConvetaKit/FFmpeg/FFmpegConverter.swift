import CoreGraphics
import Foundation

/// Converts with the bundled FFmpeg: every format Apple's frameworks can't write, and every
/// source they can't read. H.264, HEVC and ProRes still use VideoToolbox through FFmpeg.
struct FFmpegConverter: Converter {
    let tools: FFmpegTools

    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput {
        let arguments = try Self.arguments(for: request)
        let duration = request.settings.outputDuration(source: request.info.duration) ?? 0
        let throttle = ProgressThrottle(progress)
        let onLine: @Sendable (String) -> Void = { line in
            // -progress reports "out_time_us=12345678" several times a second.
            guard duration > 0, line.hasPrefix("out_time_us="), let micros = Double(line.dropFirst(12)) else { return }
            throttle.report(micros / 1_000_000 / duration * 0.99)
        }
        do {
            try await ToolRunner.run(tools.ffmpeg, arguments, onLine: onLine)
        } catch let failure as ToolRunner.Failure where Self.isSubtitleProblem(failure.message) {
            // Picture-based subtitles (Blu-ray, DVD) can't become text tracks; convert without them.
            do {
                try await ToolRunner.run(tools.ffmpeg, Self.withoutSubtitles(arguments), onLine: onLine)
            } catch let failure as ToolRunner.Failure {
                throw ConversionError.failed(Self.explain(failure.message, format: request.settings.format))
            }
        } catch let failure as ToolRunner.Failure {
            throw ConversionError.failed(Self.explain(failure.message, format: request.settings.format))
        }
        throttle.report(1)
        return .file
    }

    static func isSubtitleProblem(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("subtitle") && (lower.contains("encod") || lower.contains("text to text") || lower.contains("bitmap"))
    }

    /// The same command with subtitle streams dropped.
    static func withoutSubtitles(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-map", index + 1 < arguments.count, arguments[index + 1] == "0:s?" { index += 2; continue }
            if argument == "-c:s", index + 1 < arguments.count { index += 2; continue }
            result.append(argument)
            if argument == "-dn" { result.append("-sn") }
            index += 1
        }
        return result
    }

    /// The full FFmpeg command line for a request. Pure, so it is tested directly.
    static func arguments(for request: ConversionRequest) throws -> [String] {
        let settings = request.settings
        let format = settings.format
        var args = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
        if let trim = settings.trim {
            // Input options: seek before decoding (fast and, with re-encoding, frame accurate).
            args += ["-ss", String(format: "%.3f", trim.start), "-t", String(format: "%.3f", trim.duration)]
        }
        args += ["-i", request.source.path]

        switch (request.info.kind, format.kind) {
        case (.video, .video):
            args += videoArguments(settings, info: request.info)
        case (.video, .image) where format == .gif:
            args += gifArguments(settings.animation, info: request.info)
        case (.video, .audio), (.audio, .audio):
            args += ["-map", "0:a:0", "-vn", "-sn", "-dn"] + audioArguments(settings, info: request.info)
        case (.image, .image):
            args += imageArguments(settings, info: request.info)
        default:
            throw ConversionError.unsupportedConversion(from: request.info.kind, to: format)
        }
        let strip = format.kind == .image && settings.image.stripMetadata
        args += ["-map_metadata", strip ? "-1" : "0", "-f", muxer(for: format), request.destination.path]
        return args
    }

    static func muxer(for format: OutputFormat) -> String {
        switch format {
        case .mp4: "mp4"
        case .mov: "mov"
        case .m4v: "ipod"
        case .mkv: "matroska"
        case .webm: "webm"
        case .avi: "avi"
        case .gif: "gif"
        case .mp3: "mp3"
        case .m4a: "ipod"
        case .aac: "adts"
        case .wav: "wav"
        case .aiff: "aiff"
        case .flac: "flac"
        case .ogg: "ogg"
        case .opus: "opus"
        case .wma: "asf"
        case .webp: "webp"
        case .jpeg, .png, .tiff, .bmp, .heic, .avif, .pdf: "image2"
        }
    }

    // MARK: Video

    private static func videoArguments(_ settings: ConversionSettings, info: MediaInfo) -> [String] {
        let options = settings.video
        let format = settings.format
        var args = ["-map", "0:v:0"]
        if options.includeAudio, info.hasAudio { args += ["-map", "0:a:0?"] }
        // Keep subtitle tracks, in the form each container understands.
        let subtitleCodec: String? = switch format {
        case .mp4, .mov, .m4v: "mov_text"
        case .mkv: "copy"
        case .webm: "webvtt"
        default: nil
        }
        if let subtitleCodec { args += ["-map", "0:s?", "-c:s", subtitleCodec] } else { args += ["-sn"] }
        args += ["-dn"]

        let codec = format.videoCodecs.isEmpty ? nil : (format.videoCodecs.contains(options.codec) ? options.codec : .h264)
        if codec == .passthrough {
            args += ["-c:v", "copy"]
            if options.includeAudio, info.hasAudio { args += ["-c:a", "copy"] }
            if format == .mp4 || format == .m4v || format == .mov { args += ["-movflags", "+faststart"] }
            return args + (options.includeAudio ? [] : ["-an"])
        }

        var filters: [String] = []
        if let size = scaledSize(info.pixelSize, resolution: options.resolution) {
            filters.append("scale=\(Int(size.width)):\(Int(size.height)):flags=lanczos")
        }
        if options.frameRate != .original { args += ["-fpsmax", "\(options.frameRate.rawValue)"] }

        let output = scaledSize(info.pixelSize, resolution: options.resolution) ?? info.pixelSize ?? CGSize(width: 1920, height: 1080)
        let rate = min(Double(options.frameRate == .original ? 60 : options.frameRate.rawValue), info.frameRate ?? 30)
        let pixels = output.width * output.height * rate
        let audioRate: Double = format == .webm ? 128_000 : 192_000
        let target = options.targetVideoBitrate(duration: settings.outputDuration(source: info.duration), audioBitsPerSecond: audioRate)

        switch (format, codec) {
        case (.webm, _):
            let crf = [Quality.compact: 40, .balanced: 34, .high: 28, .maximum: 20][options.quality] ?? 32
            let rateControl = target.map { ["-b:v", bitrate($0)] } ?? ["-crf", "\(crf)", "-b:v", "0"]
            args += ["-c:v", "libvpx-vp9"] + rateControl + ["-row-mt", "1", "-deadline", "good", "-cpu-used", "3", "-pix_fmt", "yuv420p"]
        case (.avi, _):
            let q = [Quality.compact: 8, .balanced: 5, .high: 3, .maximum: 2][options.quality] ?? 5
            args += ["-c:v", "mpeg4"] + (target.map { ["-b:v", bitrate($0)] } ?? ["-q:v", "\(q)"]) + ["-vtag", "xvid", "-pix_fmt", "yuv420p"]
        case (_, .hevc?):
            args += ["-c:v", "hevc_videotoolbox", "-b:v", bitrate(target ?? pixels * options.quality.bitsPerPixel * 0.6), "-tag:v", "hvc1", "-pix_fmt", "yuv420p", "-allow_sw", "1"]
        case (_, .proRes422?):
            args += ["-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le"]
        case (_, .proRes4444?):
            args += ["-c:v", "prores_ks", "-profile:v", "4", "-pix_fmt", "yuva444p10le"]
        default:
            args += ["-c:v", "h264_videotoolbox", "-b:v", bitrate(target ?? pixels * options.quality.bitsPerPixel), "-profile:v", "high", "-pix_fmt", "yuv420p", "-allow_sw", "1"]
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }

        if options.includeAudio, info.hasAudio {
            switch format {
            case .webm: args += ["-c:a", "libopus", "-b:a", "128k"]
            case .avi: args += ["-c:a", "libmp3lame", "-b:a", "192k"]
            default: args += ["-c:a", "aac", "-b:a", "192k"]
            }
            args += ["-ac", "2"]
        } else {
            args += ["-an"]
        }
        if format == .mp4 || format == .m4v || format == .mov { args += ["-movflags", "+faststart"] }
        return args
    }

    /// The displayed size with the shorter side limited to `resolution`, even numbers; `nil` when unchanged.
    static func scaledSize(_ size: CGSize?, resolution: Resolution) -> CGSize? {
        guard let size, resolution != .original else { return nil }
        let shorter = min(size.width, size.height)
        guard shorter > CGFloat(resolution.rawValue) else { return nil }
        let scale = CGFloat(resolution.rawValue) / shorter
        func even(_ value: CGFloat) -> CGFloat { max(2, (value * scale / 2).rounded() * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    private static func bitrate(_ bits: Double) -> String { "\(Int(max(150_000, bits)) / 1000)k" }

    // MARK: GIF

    private static func gifArguments(_ options: AnimationOptions, info: MediaInfo) -> [String] {
        let width = Int(AnimatedGIFConverter.targetWidth(source: info.pixelSize?.width ?? 480, requested: options.width))
        let graph = "fps=\(options.framesPerSecond),scale=\(width):-2:flags=lanczos,split[a][b];"
            + "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4"
        return ["-map", "0:v:0", "-an", "-sn", "-vf", graph, "-loop", options.loops ? "0" : "-1"]
    }

    // MARK: Audio

    static func audioArguments(_ settings: ConversionSettings, info: MediaInfo) -> [String] {
        var options = settings.audio
        options.bitrate = info.effectiveAudioBitrate(options.bitrate)
        let format = settings.format
        let kbps = "\(options.bitrate)k"
        let deep = options.bitDepth == .bits24
        var args: [String]
        switch format {
        case .mp3: args = ["-c:a", "libmp3lame", "-b:a", "\(min(options.bitrate, 320))k"]
        case .aac: args = ["-c:a", "aac", "-b:a", kbps]
        case .m4a: args = options.codec == .aac ? ["-c:a", "aac", "-b:a", kbps] : ["-c:a", "alac", "-sample_fmt", deep ? "s32p" : "s16p"]
        case .ogg: args = ["-c:a", "libvorbis", "-b:a", "\(min(max(options.bitrate, 64), 320))k"]
        case .opus: args = ["-c:a", "libopus", "-b:a", "\(min(options.bitrate, 256))k"]
        case .wma: args = ["-c:a", "wmav2", "-b:a", "\(min(options.bitrate, 192))k"]
        case .flac: args = ["-c:a", "flac", "-sample_fmt", deep ? "s32" : "s16"] + (deep ? ["-bits_per_raw_sample", "24"] : [])
        case .wav: args = ["-c:a", deep ? "pcm_s24le" : "pcm_s16le"]
        case .aiff: args = ["-c:a", deep ? "pcm_s24be" : "pcm_s16be"]
        default: args = []
        }

        var rate = options.sampleRate == .original ? nil : options.sampleRate.rawValue
        if format == .opus { rate = 48_000 }
        if [.mp3, .wma, .ogg].contains(format), let chosen = rate, chosen > 48_000 { rate = 48_000 }
        if format == .mp3, rate == nil, let source = info.sampleRate, source > 48_000 { rate = 48_000 }
        if let rate { args += ["-ar", "\(rate)"] }

        switch options.channels {
        case .mono: args += ["-ac", "1"]
        case .stereo: args += ["-ac", "2"]
        case .original: if (info.channels ?? 2) > 2, ![OutputFormat.flac, .wav, .aiff].contains(format) { args += ["-ac", "2"] }
        }
        return args
    }

    // MARK: Images

    private static func imageArguments(_ settings: ConversionSettings, info: MediaInfo) -> [String] {
        let options = settings.image
        let format = settings.format
        var args = ["-map", "0:v:0"]
        if let limit = options.maxDimension {
            args += ["-vf", "scale='min(\(limit),iw)':'min(\(limit),ih)':force_original_aspect_ratio=decrease:flags=lanczos"]
        }
        let quality = Int(options.quality.imageCompression * 100)
        switch format {
        case .webp:
            let animated = info.frameCount > 1
            args += ["-c:v", animated ? "libwebp_anim" : "libwebp", "-quality", "\(quality)", "-compression_level", "5"]
            args += animated ? ["-loop", "0"] : ["-frames:v", "1"]
        case .jpeg: args += ["-c:v", "mjpeg", "-q:v", "\(max(2, 31 - quality * 29 / 100))", "-frames:v", "1", "-update", "1"]
        case .png: args += ["-c:v", "png", "-frames:v", "1", "-update", "1"]
        case .tiff: args += ["-c:v", "tiff", "-frames:v", "1", "-update", "1"]
        case .bmp: args += ["-c:v", "bmp", "-frames:v", "1", "-update", "1"]
        case .gif: args += ["-c:v", "gif"]
        default: break
        }
        return args
    }

    /// Turns FFmpeg's last error line into something a person can act on.
    static func explain(_ message: String, format: OutputFormat) -> String {
        let lower = message.lowercased()
        if lower.contains("invalid data") { return "The file couldn’t be read. It may be damaged or incomplete." }
        if lower.contains("could not find codec parameters") { return "This file has no stream Conveta can convert." }
        if lower.contains("no space left") { return "The disk is full." }
        if lower.contains("permission denied") || lower.contains("operation not permitted") { return "Conveta isn’t allowed to save in this folder." }
        if lower.contains("matches no streams") { return "This file has nothing to convert to \(format.displayName)." }
        return "The conversion to \(format.displayName) failed: \(message)"
    }
}
