import AVFoundation
import Foundation
import Testing
@testable import ConvetaKit

/// The FFmpeg helper Conveta bundles (built by scripts/build-ffmpeg.sh), or Homebrew's when that isn't built.
let testTools: FFmpegTools? = {
    let repo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Vendor/FFmpeg/bin").standardized
    return FFmpegTools.tools(in: repo) ?? FFmpegTools.tools(in: URL(filePath: "/opt/homebrew/bin"))
}()

@Suite("FFmpeg arguments")
struct FFmpegArgumentTests {
    func request(_ kind: MediaKind, _ settings: ConversionSettings, size: CGSize? = CGSize(width: 1920, height: 1080)) -> ConversionRequest {
        var info = MediaInfo(kind: kind, contentType: .data, fileSize: 1)
        info.pixelSize = size
        info.frameRate = 30
        info.hasAudio = true
        info.channels = 6
        info.sampleRate = 96_000
        return ConversionRequest(source: URL(filePath: "/in/a"), destination: URL(filePath: "/out/b"), settings: settings, info: info)
    }

    func joined(_ r: ConversionRequest) throws -> String { try FFmpegConverter.arguments(for: r).joined(separator: " ") }

    @Test("MP3 uses LAME, caps the rate and downmixes surround")
    func mp3() throws {
        var settings = ConversionSettings(format: .mp3)
        settings.audio.bitrate = 320
        let args = try joined(request(.audio, settings))
        #expect(args.contains("-c:a libmp3lame -b:a 320k"))
        #expect(args.contains("-ar 48000"))
        #expect(args.contains("-ac 2"))
        #expect(args.contains("-vn"))
        #expect(args.hasSuffix("-f mp3 /out/b"))
    }

    @Test("Lossless keeps surround and honours bit depth")
    func flac() throws {
        var settings = ConversionSettings(format: .flac)
        settings.audio.bitDepth = .bits24
        let args = try joined(request(.audio, settings))
        #expect(args.contains("-c:a flac -sample_fmt s32 -bits_per_raw_sample 24"))
        #expect(!args.contains("-ac"))
    }

    @Test("WebM is VP9 with Opus; resolution scales the short side")
    func webm() throws {
        var settings = ConversionSettings(format: .webm)
        settings.video.resolution = .p720
        let args = try joined(request(.video, settings))
        #expect(args.contains("-c:v libvpx-vp9"))
        #expect(args.contains("-c:a libopus"))
        #expect(args.contains("scale=1280:720"))
    }

    @Test("MKV with H.264 uses VideoToolbox; copy keeps streams")
    func mkv() throws {
        var settings = ConversionSettings(format: .mkv)
        #expect(try joined(request(.video, settings)).contains("-c:v h264_videotoolbox"))
        settings.video.codec = .passthrough
        let copy = try joined(request(.video, settings))
        #expect(copy.contains("-c:v copy"))
        #expect(copy.contains("-c:a copy"))
        #expect(!copy.contains("scale="))
    }

    @Test("Removing audio and lowering frame rate")
    func noAudio() throws {
        var settings = ConversionSettings(format: .avi)
        settings.video.includeAudio = false
        settings.video.frameRate = .fps24
        let args = try joined(request(.video, settings))
        #expect(args.contains("-an"))
        #expect(args.contains("-fpsmax 24"))
        #expect(args.contains("-c:v mpeg4"))
    }

    @Test("WebP images, metadata stripping")
    func webp() throws {
        var settings = ConversionSettings(format: .webp)
        settings.image.stripMetadata = true
        settings.image.maxDimension = 512
        let args = try joined(request(.image, settings))
        #expect(args.contains("-c:v libwebp"))
        #expect(args.contains("-map_metadata -1"))
        #expect(args.contains("min(512,iw)"))
    }

    @Test("Never upscales")
    func scale() {
        #expect(FFmpegConverter.scaledSize(CGSize(width: 640, height: 360), resolution: .p720) == nil)
        #expect(FFmpegConverter.scaledSize(CGSize(width: 1080, height: 1920), resolution: .p720) == CGSize(width: 720, height: 1280))
    }

    @Test("Errors read like sentences")
    func errors() {
        #expect(FFmpegConverter.explain("pipe:: Invalid data found when processing input", format: .mp3) == "The file couldn’t be read. It may be damaged or incomplete.")
        #expect(FFmpegConverter.explain("weird", format: .mp3).hasPrefix("The conversion to MP3 failed"))
    }

    @Test("ffprobe frame rates")
    func rates() {
        #expect(FFprobe.rate("30000/1001").map { ($0 * 100).rounded() / 100 } == 29.97)
        #expect(FFprobe.rate("0/0") == nil)
        #expect(FFprobe.rate("25") == 25)
    }
}

@Suite("FFmpeg conversions", .serialized, .enabled(if: testTools != nil))
struct FFmpegConversionTests {
    let tools = testTools!

    func make(_ fixtures: Fixtures, _ name: String, _ ffmpegArgs: [String]) async throws -> URL {
        let url = fixtures.url(name)
        try await ToolRunner.run(tools.ffmpeg, ["-v", "error", "-y"] + ffmpegArgs + [url.path])
        return url
    }

    func convert(_ source: URL, _ settings: ConversionSettings, _ fixtures: Fixtures) async throws -> (URL, MediaInfo) {
        let service = ConversionService(tools: tools)
        let info = try await MediaProbe.probe(source, tools: tools)
        let out = fixtures.folder.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let result = try await service.convert(source, info: info, settings: settings, into: out)
        return (result, try await MediaProbe.probe(result, tools: tools))
    }

    func codec(_ url: URL) async throws -> String {
        try await ToolRunner.run(tools.ffprobe, ["-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", url.path])
            .split(whereSeparator: \.isNewline).joined(separator: ",")
    }

    @Test("Audio to every FFmpeg format", arguments: [
        (OutputFormat.mp3, "mp3"), (.aac, "aac"), (.ogg, "vorbis"), (.wma, "wmav2"),
    ])
    func audio(format: OutputFormat, expected: String) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeTone("Voice Note.wav", seconds: 3)
        let (output, info) = try await convert(source, ConversionSettings(format: format), fixtures)
        #expect(output.lastPathComponent == "Voice Note.\(format.fileExtension)")
        #expect(try await codec(output) == expected)
        #expect(abs((info.duration ?? 0) - 3) < 0.15)
    }

    @Test("Video to MKV, WebM and AVI", arguments: [
        (OutputFormat.mkv, "h264,aac"), (.webm, "vp9,opus"), (.avi, "mpeg4,mp3"),
    ])
    func video(format: OutputFormat, expected: String) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov", seconds: 1.5)
        let (output, info) = try await convert(movie, ConversionSettings(format: format), fixtures)
        #expect(try await codec(output) == expected)
        #expect(info.pixelSize == CGSize(width: 640, height: 360))
        #expect(info.hasAudio)
    }

    @Test("MKV with Vorbis in: read by ffprobe, converted to MP4 and MP3")
    func mkvSource() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try await make(fixtures, "Old Clip.mkv", ["-f", "lavfi", "-i", "testsrc=size=320x240:rate=25", "-f", "lavfi", "-i", "sine=frequency=500",
                                                             "-t", "2", "-c:v", "libvpx-vp9", "-c:a", "libvorbis"])
        let probed = try await MediaProbe.probe(source, tools: tools)
        #expect(probed.kind == .video)
        #expect(!probed.readableByApple)
        #expect(probed.pixelSize == CGSize(width: 320, height: 240))
        #expect(probed.codec == "VP9")
        await #expect(throws: (any Error).self) { try await MediaProbe.probe(source) }

        let (mp4, mp4Info) = try await convert(source, ConversionSettings(format: .mp4), fixtures)
        #expect(try await codec(mp4) == "h264,aac")
        #expect(mp4Info.readableByApple)
        let (mp3, _) = try await convert(source, ConversionSettings(format: .mp3), fixtures)
        #expect(try await codec(mp3) == "mp3")
        let (gif, _) = try await convert(source, ConversionSettings(format: .gif), fixtures)
        #expect(Inspect.frameCount(gif) == 30)
    }

    @Test("WMA and Ogg Vorbis in: read and converted to M4A natively after FFmpeg")
    func wmaSource() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let wma = try await make(fixtures, "Song.wma", ["-f", "lavfi", "-i", "sine=frequency=440", "-t", "2", "-c:a", "wmav2"])
        let info = try await MediaProbe.probe(wma, tools: tools)
        #expect(info.kind == .audio)
        #expect(info.codec == "WMA")
        let (m4a, _) = try await convert(wma, ConversionSettings(format: .m4a), fixtures)
        #expect(try await codec(m4a) == "aac")
        let (flac, _) = try await convert(wma, ConversionSettings(format: .flac), fixtures)
        #expect(try await codec(flac) == "flac")
    }

    @Test("Images to WebP, still and animated")
    func webp() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let png = try fixtures.writeImage("Photo.png", type: .png, width: 800, height: 600, alpha: true)
        var settings = ConversionSettings(format: .webp)
        settings.image.maxDimension = 400
        let (still, _) = try await convert(png, settings, fixtures)
        #expect(Inspect.imageType(still) == "org.webmproject.webp")
        #expect(Inspect.imageSize(still) == CGSize(width: 400, height: 300))

        let gif = try fixtures.writeAnimatedGIF("Loop.gif", frames: 5)
        let (animated, _) = try await convert(gif, ConversionSettings(format: .webp), fixtures)
        #expect(Inspect.frameCount(animated) == 5)
    }

    @Test("Cancelling FFmpeg stops the process and leaves nothing")
    func cancel() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let long = try fixtures.writeTone("Long.wav", seconds: 900)
        let info = try await MediaProbe.probe(long, tools: tools)
        let out = fixtures.folder.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let service = ConversionService(tools: tools)
        let task = Task { try await service.convert(long, info: info, settings: ConversionSettings(format: .mp3), into: out) }
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test("Damaged files fail with a readable message")
    func damaged() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let fake = fixtures.url("Broken.mkv")
        try Data(repeating: 7, count: 4096).write(to: fake)
        await #expect(throws: ProbeError.unreadable("Broken.mkv")) { try await MediaProbe.probe(fake, tools: tools) }
    }
}

@Suite("Tool runner")
struct ToolRunnerTests {
    @Test("Cancelling before launch never touches the process")
    func cancelBeforeLaunch() async {
        for _ in 0..<50 {
            let task = Task { try await ToolRunner.run(URL(filePath: "/bin/sleep"), ["5"]) }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test("Failures carry the last error line")
    func failure() async {
        do {
            try await ToolRunner.run(URL(filePath: "/bin/sh"), ["-c", "echo first >&2; echo 'last words' >&2; exit 3"])
            Issue.record("expected a failure")
        } catch let failure as ToolRunner.Failure {
            #expect(failure.status == 3)
            #expect(failure.message == "last words")
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test("Output lines stream as they arrive")
    func lines() async throws {
        let seen = Recorder()
        let output = try await ToolRunner.run(URL(filePath: "/bin/sh"), ["-c", "echo 1; echo 2; echo 3"]) { line in
            if let value = Double(line) { seen.add(value) }
        }
        #expect(output == "1\n2\n3\n")
        #expect(seen.all == [1, 2, 3])
    }
}

@Suite("Bitrate never inflates")
struct BitrateTests {
    func info(_ codec: String, _ kbps: Int?, kind: MediaKind = .audio) -> MediaInfo {
        var info = MediaInfo(kind: kind, contentType: .data, fileSize: 1)
        info.codec = codec
        info.audioBitrate = kbps
        return info
    }

    @Test("Lossy sources cap the rate at the next step up from theirs")
    func cap() {
        #expect(info("MP3", 64).effectiveAudioBitrate(256) == 64)
        #expect(info("AAC", 100).effectiveAudioBitrate(256) == 128)
        #expect(info("Opus", 24).effectiveAudioBitrate(256) == 64)
        #expect(info("MP3", 320).effectiveAudioBitrate(192) == 192)
    }

    @Test("Lossless or unknown sources keep the request")
    func keep() {
        #expect(info("PCM", 1411).effectiveAudioBitrate(256) == 256)
        #expect(info("FLAC", 900).effectiveAudioBitrate(320) == 320)
        #expect(info("MP3", nil).effectiveAudioBitrate(256) == 256)
    }
}
