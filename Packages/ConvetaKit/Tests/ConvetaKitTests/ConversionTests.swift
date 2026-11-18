import AVFoundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ConvetaKit

/// End-to-end conversions on real files produced by ``Fixtures``.
@Suite("Conversions", .serialized)
struct ConversionTests {
    let service = ConversionService(tools: testTools)

    private func run(_ source: URL, _ settings: ConversionSettings, in fixtures: Fixtures) async throws -> URL {
        let info = try await MediaProbe.probe(source, tools: testTools)
        let out = fixtures.folder.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let result = try await service.convert(source, info: info, settings: settings, into: out)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: out.path).filter { $0.hasPrefix(".conveta-") }
        #expect(leftovers.isEmpty, "working files left behind: \(leftovers)")
        return result
    }

    // MARK: Images

    @Test("Image to every image format", arguments: MediaKind.image.outputFormats)
    func imageToFormat(format: OutputFormat) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeImage("Photo.png", type: .png, alpha: true)
        let output = try await run(source, ConversionSettings(format: format), in: fixtures)
        #expect(output.lastPathComponent == "Photo.\(format.fileExtension)")
        if format == .webp {
            #expect(Inspect.imageType(output) == "org.webmproject.webp")
            #expect(Inspect.imageSize(output) == CGSize(width: 300, height: 200))
        } else if format == .pdf {
            let document = try #require(CGPDFDocument(output as CFURL))
            #expect(document.numberOfPages == 1)
            #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 300, height: 200))
        } else {
            #expect(Inspect.imageType(output) == format.contentType.identifier)
            #expect(Inspect.imageSize(output) == CGSize(width: 300, height: 200))
        }
    }

    @Test("Resizing limits the longest side and never upscales")
    func imageResize() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeImage("Wide.jpg", type: .jpeg, width: 1200, height: 600)
        var settings = ConversionSettings(format: .png)
        settings.image.maxDimension = 512
        #expect(Inspect.imageSize(try await run(source, settings, in: fixtures)) == CGSize(width: 512, height: 256))
        settings.image.maxDimension = 4096
        #expect(Inspect.imageSize(try await run(source, settings, in: fixtures)) == CGSize(width: 1200, height: 600))
    }

    @Test("Orientation is applied to the pixels and reset in metadata")
    func orientation() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeImage("Portrait.jpg", type: .jpeg, width: 400, height: 300,
                                             properties: [kCGImagePropertyOrientation: 6])
        let output = try await run(source, ConversionSettings(format: .png), in: fixtures)
        #expect(Inspect.imageSize(output) == CGSize(width: 300, height: 400))
        #expect((Inspect.properties(output)[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test("Metadata is kept, or stripped on request")
    func metadata() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 52.2, kCGImagePropertyGPSLatitudeRef: "N"]
        let source = try fixtures.writeImage("Trip.jpg", type: .jpeg, properties: [kCGImagePropertyGPSDictionary: gps])
        var settings = ConversionSettings(format: .heic)
        #expect(Inspect.properties(try await run(source, settings, in: fixtures))[kCGImagePropertyGPSDictionary] != nil)
        settings.image.stripMetadata = true
        #expect(Inspect.properties(try await run(source, settings, in: fixtures))[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test("Lower quality makes smaller JPEGs")
    func jpegQuality() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeImage("Big.png", type: .png, width: 1600, height: 1200)
        var settings = ConversionSettings(format: .jpeg)
        settings.image.quality = .maximum
        let large = try await run(source, settings, in: fixtures)
        settings.image.quality = .compact
        let small = try await run(source, settings, in: fixtures)
        #expect(try small.resourceValues(forKeys: [.fileSizeKey]).fileSize! < large.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
    }

    @Test("Animated GIF stays animated; other formats take the first frame")
    func animatedGIF() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeAnimatedGIF("Loop.gif", frames: 6)
        #expect(try await MediaProbe.probe(source).frameCount == 6)
        #expect(Inspect.frameCount(try await run(source, ConversionSettings(format: .gif), in: fixtures)) == 6)
        #expect(Inspect.frameCount(try await run(source, ConversionSettings(format: .png), in: fixtures)) == 1)
    }

    @Test("Unreadable images fail cleanly")
    func corruptImage() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = fixtures.url("Broken.png")
        try Data("not an image".utf8).write(to: source)
        await #expect(throws: ProbeError.unreadable("Broken.png")) { try await MediaProbe.probe(source) }
    }

    @Test("Unsupported files are refused by the probe")
    func unsupported() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = fixtures.url("Notes.txt")
        try Data("hello".utf8).write(to: source)
        await #expect(throws: ProbeError.unsupportedType("txt")) { try await MediaProbe.probe(source) }
    }

    // MARK: PDF

    @Test("A one-page PDF becomes one image")
    func pdfSinglePage() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writePDF("Letter.pdf", pages: 1)
        var settings = ConversionSettings(format: .png)
        settings.document.dotsPerInch = 144
        let output = try await run(source, settings, in: fixtures)
        #expect(output.lastPathComponent == "Letter.png")
        #expect(Inspect.imageSize(output) == CGSize(width: 1224, height: 1584))
    }

    @Test("A multi-page PDF becomes a folder of sorted pages")
    func pdfPages() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writePDF("Deck.pdf", pages: 3)
        #expect(try await MediaProbe.probe(source).pageCount == 3)
        var settings = ConversionSettings(format: .jpeg)
        settings.document.dotsPerInch = 72
        let output = try await run(source, settings, in: fixtures)
        #expect(output.lastPathComponent == "Deck")
        let pages = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        #expect(pages == ["1.jpg", "2.jpg", "3.jpg"])
        #expect(Inspect.imageSize(output.appending(path: "2.jpg")) == CGSize(width: 792, height: 612))
    }

    // MARK: Audio

    @Test("Audio to every audio format", arguments: MediaKind.audio.outputFormats)
    func audioToFormat(format: OutputFormat) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeTone("Tone.wav", seconds: 1.5)
        let output = try await run(source, ConversionSettings(format: format), in: fixtures)
        #expect(output.pathExtension == format.fileExtension)
        let info = try await MediaProbe.probe(output, tools: testTools)
        #expect(info.kind == .audio)
        #expect(abs((info.duration ?? 0) - 1.5) < 0.1)
        #expect(info.channels == 2)
        #expect(info.sampleRate == (format == .opus ? 48_000 : 44_100))
    }

    @Test("Codec, rate, channels and bit depth follow the options")
    func audioOptions() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeTone("Tone.wav", sampleRate: 48_000)

        var settings = ConversionSettings(format: .m4a)
        settings.audio.codec = .alac
        settings.audio.sampleRate = .hz44100
        settings.audio.channels = .mono
        let alac = try await run(source, settings, in: fixtures)
        #expect(try await Inspect.codec(alac, .audio) == kAudioFormatAppleLossless)
        let alacFormat = try Inspect.audioFormat(alac)
        #expect(alacFormat.mSampleRate == 44_100)
        #expect(alacFormat.mChannelsPerFrame == 1)

        settings = ConversionSettings(format: .wav)
        settings.audio.bitDepth = .bits24
        let wav = try await run(source, settings, in: fixtures)
        #expect(try Inspect.audioFormat(wav).mBitsPerChannel == 24)

        settings = ConversionSettings(format: .m4a)
        settings.audio.bitrate = 64
        let small = try await run(source, settings, in: fixtures)
        settings.audio.bitrate = 320
        let large = try await run(source, settings, in: fixtures)
        #expect(try small.resourceValues(forKeys: [.fileSizeKey]).fileSize! < large.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
    }

    @Test("Audio is extracted from video")
    func audioFromVideo() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov")
        let output = try await run(movie, ConversionSettings(format: .m4a), in: fixtures)
        #expect(try await Inspect.codec(output, .audio) == kAudioFormatMPEG4AAC)
        #expect(try await AVURLAsset(url: output).loadTracks(withMediaType: .video).isEmpty)
    }

    @Test("A silent video can't become audio")
    func silentVideoToAudio() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Silent.mov", withAudio: false)
        await #expect(throws: ConversionError.noAudioTrack) {
            _ = try await self.run(movie, ConversionSettings(format: .wav), in: fixtures)
        }
        let out = fixtures.folder.appending(path: "out")
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    // MARK: Video

    @Test("Video codecs in every container", arguments: [
        (OutputFormat.mp4, VideoCodec.h264, kCMVideoCodecType_H264),
        (.mp4, .hevc, kCMVideoCodecType_HEVC),
        (.m4v, .h264, kCMVideoCodecType_H264),
        (.mov, .proRes422, kCMVideoCodecType_AppleProRes422),
        (.mov, .proRes4444, kCMVideoCodecType_AppleProRes4444),
        (.mov, .passthrough, kCMVideoCodecType_H264),
        (.mp4, .passthrough, kCMVideoCodecType_H264),
    ])
    func videoCodecs(format: OutputFormat, codec: VideoCodec, expected: CMVideoCodecType) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov")
        var settings = ConversionSettings(format: format)
        settings.video.codec = codec
        let output = try await run(movie, settings, in: fixtures)
        #expect(output.pathExtension == format.fileExtension)
        #expect(try await Inspect.codec(output, .video) == expected)
        let info = try await MediaProbe.probe(output)
        #expect(info.pixelSize == CGSize(width: 640, height: 360))
        #expect(abs((info.duration ?? 0) - 1.5) < 0.1)
        #expect(info.hasAudio)
    }

    @Test("Resolution, frame rate and audio removal")
    func videoOptions() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov", width: 1280, height: 720, fps: 60)
        var settings = ConversionSettings(format: .mp4)
        settings.video.resolution = .p480
        settings.video.frameRate = .fps30
        settings.video.includeAudio = false
        let output = try await run(movie, settings, in: fixtures)
        let info = try await MediaProbe.probe(output)
        #expect(info.pixelSize == CGSize(width: 854, height: 480))
        #expect(!info.hasAudio)
        let samples = try await Self.videoFrameCount(output)
        #expect((44...46).contains(samples), "expected about 45 frames at 30 fps, got \(samples)")
    }

    @Test("Rotation survives re-encoding")
    func rotation() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Phone.mov", rotated: true)
        #expect(try await MediaProbe.probe(movie).pixelSize == CGSize(width: 360, height: 640))
        var settings = ConversionSettings(format: .mp4)
        settings.video.resolution = .p480
        #expect(try await MediaProbe.probe(try await run(movie, settings, in: fixtures)).pixelSize == CGSize(width: 360, height: 640))
    }

    @Test("Higher quality makes larger files")
    func videoQuality() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov", withAudio: false)
        var settings = ConversionSettings(format: .mp4)
        settings.video.quality = .compact
        let small = try await run(movie, settings, in: fixtures)
        settings.video.quality = .maximum
        let large = try await run(movie, settings, in: fixtures)
        #expect(try small.resourceValues(forKeys: [.fileSizeKey]).fileSize! < large.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
    }

    @Test("Video to animated GIF")
    func videoToGIF() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov", seconds: 2)
        var settings = ConversionSettings(format: .gif)
        settings.animation.framesPerSecond = 10
        settings.animation.width = 320
        let output = try await run(movie, settings, in: fixtures)
        #expect(Inspect.imageType(output) == UTType.gif.identifier)
        #expect(Inspect.frameCount(output) == 20)
        #expect(Inspect.imageSize(output) == CGSize(width: 320, height: 180))
    }

    @Test("Progress rises to 1 and cancellation leaves nothing behind")
    func progressAndCancel() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov", width: 1280, height: 720, seconds: 3)
        let info = try await MediaProbe.probe(movie)
        let out = fixtures.folder.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let values = Recorder()
        var settings = ConversionSettings(format: .mov)
        settings.video.codec = .proRes422
        _ = try await service.convert(movie, info: info, settings: settings, into: out) { values.add($0) }
        let reported = values.all
        #expect(reported.last == 1)
        #expect(reported == reported.sorted())

        // Cancel as soon as the conversion reports progress, not after a guessed delay.
        let started = AsyncStream<Void>.makeStream()
        let task = Task {
            try await service.convert(movie, info: info, settings: settings, into: out) { value in
                if value > 0 { started.continuation.yield() }
            }
        }
        for await _ in started.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(files == ["Clip.mov"], "cancelled job left \(files)")
    }

    static func videoFrameCount(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var count = 0
        while let sample = output.copyNextSampleBuffer() { count += CMSampleBufferGetNumSamples(sample) }
        return count
    }
}

final class Recorder: Sendable {
    private let values = OSAllocatedUnfairLock(initialState: [Double]())
    func add(_ value: Double) { values.withLock { $0.append(value) } }
    var all: [Double] { values.withLock { $0 } }
}

import os

/// Cross-checks outputs with FFmpeg's decoder when it is installed, so files open outside Apple's stack too.
let ffprobePath = "/opt/homebrew/bin/ffprobe"

@Suite("Interoperability", .enabled(if: FileManager.default.isExecutableFile(atPath: ffprobePath)))
struct Interop {
    static let ffprobe = ffprobePath

    static func probe(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: ffprobe)
        process.arguments = ["-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:format=format_name,duration", "-of", "compact", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test("Opus files are valid Ogg Opus with the right length")
    func opusInOgg() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeTone("Tone.wav", seconds: 2.5)
        let output = try await ConversionService().convert(source, info: try await MediaProbe.probe(source),
                                                           settings: ConversionSettings(format: .opus), into: fixtures.folder)
        let report = try Self.probe(output)
        #expect(report.contains("codec_name=opus"), "\(report)")
        #expect(report.contains("format_name=ogg"), "\(report)")
        let duration = report.components(separatedBy: "duration=").last.flatMap { Double($0.prefix(8)) } ?? 0
        #expect(abs(duration - 2.5) < 0.03, "\(report)")
    }

    @Test("FLAC and ALAC decode outside Apple's stack", arguments: [OutputFormat.flac, .m4a])
    func lossless(format: OutputFormat) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let source = try fixtures.writeTone("Tone.wav")
        var settings = ConversionSettings(format: format)
        settings.audio.codec = .alac
        let output = try await ConversionService().convert(source, info: try await MediaProbe.probe(source), settings: settings, into: fixtures.folder)
        #expect(try Self.probe(output).contains(format == .flac ? "codec_name=flac" : "codec_name=alac"))
    }
}
