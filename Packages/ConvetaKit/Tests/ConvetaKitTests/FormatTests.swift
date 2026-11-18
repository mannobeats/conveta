import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ConvetaKit

@Suite("Formats and naming")
struct FormatTests {
    @Test("Each kind offers its default format first", arguments: MediaKind.allCases)
    func defaultIsOffered(kind: MediaKind) {
        #expect(kind.outputFormats.first == kind.defaultFormat)
    }

    @Test("Every format is reachable from at least one kind", arguments: OutputFormat.allCases)
    func everyFormatReachable(format: OutputFormat) {
        #expect(MediaKind.allCases.contains { $0.outputFormats.contains(format) })
    }

    static func info(_ kind: MediaKind, apple: Bool = true) -> MediaInfo {
        var info = MediaInfo(kind: kind, contentType: .data, fileSize: 0)
        info.readableByApple = apple
        return info
    }

    @Test("Every pair routes: native formats to Apple's frameworks, the rest to FFmpeg")
    func everyPairRoutes() throws {
        let tools = FFmpegTools(ffmpeg: URL(filePath: "/x/ffmpeg"), ffprobe: URL(filePath: "/x/ffprobe"))
        let service = ConversionService(tools: tools)
        for kind in MediaKind.allCases {
            for format in kind.outputFormats {
                let converter = try service.converter(for: Self.info(kind), format: format)
                #expect((converter is FFmpegConverter) == !format.isNative, "\(kind) → \(format)")
                if kind != .document, kind != .image {
                    #expect(try service.converter(for: Self.info(kind, apple: false), format: format) is FFmpegConverter)
                }
            }
        }
    }

    @Test("Without the helper, FFmpeg-only formats explain themselves")
    func noHelper() {
        #expect(throws: ConversionError.encoderUnavailable("MP3")) {
            try ConversionService().converter(for: Self.info(.audio), format: .mp3)
        }
    }

    @Test("Impossible pairs are refused")
    func impossiblePairs() {
        let service = ConversionService()
        #expect(throws: ConversionError.unsupportedConversion(from: .audio, to: .mp4)) {
            try service.converter(for: Self.info(.audio), format: .mp4)
        }
        #expect(throws: ConversionError.self) { try service.converter(for: Self.info(.image), format: .wav) }
        #expect(throws: ConversionError.self) { try service.converter(for: Self.info(.document), format: .pdf) }
    }

    @Test("Common formats of mixed kinds")
    func commonFormats() {
        #expect(MediaKind.commonFormats(for: [.video, .audio]) == [.mp3, .m4a, .aac, .wav, .aiff, .flac, .ogg, .opus, .wma])
        #expect(MediaKind.commonFormats(for: [.image, .document]) == [.jpeg, .png, .heic, .tiff])
        #expect(MediaKind.commonFormats(for: [.video, .image]) == [.gif])
        #expect(MediaKind.commonFormats(for: [.audio, .image]).isEmpty)
        #expect(MediaKind.commonFormats(for: [MediaKind]()).isEmpty)
    }

    @Test("Content types map to kinds")
    func kinds() {
        #expect(MediaKind(contentType: .quickTimeMovie) == .video)
        #expect(MediaKind(contentType: .mpeg4Movie) == .video)
        #expect(MediaKind(contentType: .mp3) == .audio)
        #expect(MediaKind(contentType: .mpeg4Audio) == .audio)
        #expect(MediaKind(contentType: .heic) == .image)
        #expect(MediaKind(contentType: .webP) == .image)
        #expect(MediaKind(contentType: .pdf) == .document)
        #expect(MediaKind(contentType: .plainText) == nil)
        #expect(MediaKind(contentType: .zip) == nil)
        #expect(MediaKind(contentType: .folder) == nil)
        #expect(MediaKind(url: URL(filePath: "/tmp/a.mkv")) == .video)
        #expect(MediaKind(url: URL(filePath: "/tmp/a.WMA")) == .audio)
        #expect(MediaKind(url: URL(filePath: "/tmp/a.ape")) == .audio)
        #expect(MediaKind(url: URL(filePath: "/tmp/a.flv")) == .video)
        #expect(MediaKind(url: URL(filePath: "/tmp/a.zip")) == nil)
        #expect(MediaKind(url: URL(filePath: "/tmp/a")) == nil)
    }

    @Test("Extensions and content types agree", arguments: OutputFormat.allCases)
    func extensionsMatchTypes(format: OutputFormat) {
        let type = UTType(filenameExtension: format.fileExtension)
        if let type, format != .opus, format != .wma, format != .aac {
            #expect(type.conforms(to: format.contentType))
        }
    }

    @Test("Output names never collide")
    func naming() throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let first = OutputNaming.candidate(in: fixtures.folder, baseName: "Clip", pathExtension: "mp4", attempt: 1)
        #expect(first.lastPathComponent == "Clip.mp4")
        #expect(OutputNaming.candidate(in: fixtures.folder, baseName: "Clip", pathExtension: "mp4", attempt: 3).lastPathComponent == "Clip 3.mp4")
        #expect(OutputNaming.candidate(in: fixtures.folder, baseName: "Scan", pathExtension: nil, attempt: 2).lastPathComponent == "Scan 2")

        var placed: [String] = []
        for _ in 0..<3 {
            let working = fixtures.url(".work-\(UUID().uuidString)")
            try Data("x".utf8).write(to: working)
            placed.append(try OutputNaming.moveIntoPlace(working, in: fixtures.folder, baseName: "Clip", pathExtension: "mp4").lastPathComponent)
        }
        #expect(placed == ["Clip.mp4", "Clip 2.mp4", "Clip 3.mp4"])
    }

    @Test("Duration formatting")
    func durations() {
        #expect(MediaInfo.formatDuration(0) == "0:00")
        #expect(MediaInfo.formatDuration(42.4) == "0:42")
        #expect(MediaInfo.formatDuration(61) == "1:01")
        #expect(MediaInfo.formatDuration(3_725) == "1:02:05")
    }

    @Test("Video target size keeps aspect, stays even, never upscales")
    func targetSize() {
        #expect(VideoConverter.targetSize(natural: CGSize(width: 3840, height: 2160), resolution: .p1080) == CGSize(width: 1920, height: 1080))
        #expect(VideoConverter.targetSize(natural: CGSize(width: 1280, height: 720), resolution: .p1080) == CGSize(width: 1280, height: 720))
        #expect(VideoConverter.targetSize(natural: CGSize(width: 1080, height: 1920), resolution: .p720) == CGSize(width: 720, height: 1280))
        #expect(VideoConverter.targetSize(natural: CGSize(width: 1001, height: 563), resolution: .original) == CGSize(width: 1002, height: 564))
        #expect(VideoConverter.targetSize(natural: CGSize(width: 640, height: 360), resolution: .p480) == CGSize(width: 640, height: 360))
    }

    @Test("GIF width is capped and never upscaled")
    func gifWidth() {
        #expect(AnimatedGIFConverter.targetWidth(source: 1920, requested: 480) == 480)
        #expect(AnimatedGIFConverter.targetWidth(source: 320, requested: 480) == 320)
        #expect(AnimatedGIFConverter.targetWidth(source: 3840, requested: nil) == 1280)
    }

    @Test("Settings round-trip through JSON")
    func settingsCodable() throws {
        var settings = ConversionSettings(format: .heic)
        settings.image.maxDimension = 2048
        settings.video.codec = .hevc
        settings.audio.bitrate = 320
        let decoded = try JSONDecoder().decode(ConversionSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}

@Suite("Hand-off from Finder")
struct HandoffTests {
    let store = HandoffStore(suiteName: "ConvetaTests-\(UUID().uuidString)")

    @Test("A request is taken exactly once")
    func takeOnce() {
        let request = HandoffRequest(paths: ["/tmp/a.mov", "/tmp/b.mov"], format: .mp4)
        store.save(request)
        #expect(store.take(request.id) == request)
        #expect(store.take(request.id) == nil)
    }

    @Test("Old requests expire")
    func expiry() {
        let old = HandoffRequest(paths: ["/tmp/a.mov"], format: nil, createdAt: .now.addingTimeInterval(-HandoffStore.lifetime - 1))
        store.save(old)
        #expect(store.take(old.id) == nil)
    }

    @Test("URLs round-trip; other URLs are ignored")
    func urls() {
        let request = HandoffRequest(paths: ["/tmp/a.png"], format: .jpeg)
        #expect(HandoffStore.requestID(in: HandoffStore.url(for: request)) == request.id)
        #expect(HandoffStore.requestID(in: URL(string: "conveta://handoff")!) == nil)
        #expect(HandoffStore.requestID(in: URL(string: "conveta://handoff?id=nope")!) == nil)
        #expect(HandoffStore.requestID(in: URL(string: "conveta://convert?id=\(request.id)")!) == nil)
        #expect(HandoffStore.requestID(in: URL(string: "https://handoff?id=\(request.id)")!) == nil)
    }
}
