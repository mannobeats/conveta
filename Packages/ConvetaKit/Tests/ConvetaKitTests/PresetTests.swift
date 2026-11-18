import AVFoundation
import Foundation
import Testing
@testable import ConvetaKit

@Suite("Presets, trim and size limits", .serialized)
struct PresetTests {
    @Test("Built-in presets are valid and have unique ids")
    func builtIns() {
        let ids = Preset.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
        for preset in Preset.builtIn {
            #expect(MediaKind.allCases.contains(where: preset.applies(to:)), "\(preset.name) suits nothing")
        }
    }

    @Test("Presets are offered only where every file can use them")
    func suiting() {
        let video = Preset.suiting([MediaKind.video], from: Preset.builtIn).map(\.id)
        #expect(video.contains("discord") && video.contains("podcast") && video.contains("gif"))
        #expect(!video.contains("web-images"))
        let mixed = Preset.suiting([MediaKind.video, .audio], from: Preset.builtIn).map(\.id)
        #expect(mixed.contains("podcast") && !mixed.contains("discord"))
        #expect(Preset.suiting([MediaKind](), from: Preset.builtIn).isEmpty)
    }

    @Test("Applying a preset keeps the file's own trim, height and subtitles")
    func applyKeeps() {
        var current = ConversionSettings(format: .mov)
        current.trim = TrimRange(start: 2, end: 5)
        current.downloadHeight = 720
        let applied = Preset.builtIn.first { $0.id == "discord" }!.apply(to: current)
        #expect(applied.format == .mp4)
        #expect(applied.trim == current.trim)
        #expect(applied.downloadHeight == 720)
        #expect(applied.video.targetMegabytes == 10)
    }

    @Test("Custom presets round-trip through the store, newest first")
    func store() {
        let store = PresetStore(suiteName: "ConvetaPresetTests-\(UUID().uuidString)")
        #expect(store.custom.isEmpty)
        let a = Preset(name: "A", summary: "", settings: ConversionSettings(format: .mp3))
        let b = Preset(name: "B", summary: "", settings: ConversionSettings(format: .png))
        store.save(a)
        store.save(b)
        #expect(store.custom.map(\.name) == ["B", "A"])
        #expect(store.preset(id: "discord")?.isBuiltIn == true)
        store.delete(a.id)
        #expect(store.custom.map(\.name) == ["B"])
    }

    @Test("Size targets leave room for sound and the container")
    func targetBitrate() {
        var options = VideoOptions()
        #expect(options.targetVideoBitrate(duration: 60, audioBitsPerSecond: 192_000) == nil)
        options.targetMegabytes = 10
        let rate = options.targetVideoBitrate(duration: 60, audioBitsPerSecond: 192_000)!
        #expect(abs(rate - (10 * 8_000_000 * 0.96 / 60 - 192_000)) < 1)
        #expect(options.targetVideoBitrate(duration: 3_600, audioBitsPerSecond: 192_000) == 150_000)
    }

    @Test("Trim ranges")
    func trims() {
        let range = TrimRange(start: -3, end: 2)
        #expect(range.start == 0 && range.end == 2)
        #expect(TrimRange(start: 5, end: 1).duration == 0)
        #expect(TrimRange(start: 0, end: 10).meaningful(for: 10) == nil)
        #expect(TrimRange(start: 1, end: 10).meaningful(for: 10) != nil)
        var settings = ConversionSettings(format: .mp4)
        settings.trim = TrimRange(start: 1, end: 4)
        #expect(settings.outputDuration(source: 10) == 3)
        #expect(settings.outputDuration(source: 2.5) == 1.5)
    }

    @Test("Trimmed video, audio and GIF have the trimmed length", arguments: [OutputFormat.mp4, .m4a, .gif, .mp3, .webm])
    func trimmedOutputs(format: OutputFormat) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Clip.mov", seconds: 4)
        var settings = ConversionSettings(format: format)
        settings.trim = TrimRange(start: 1, end: 2.5)
        settings.animation.framesPerSecond = 10
        let out = fixtures.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let service = ConversionService(tools: testTools)
        let result = try await service.convert(movie, info: try await MediaProbe.probe(movie, tools: testTools), settings: settings, into: out)
        if format == .gif {
            #expect(Inspect.frameCount(result) == 15)
        } else {
            let duration = try await MediaProbe.probe(result, tools: testTools).duration ?? 0
            #expect(abs(duration - 1.5) < 0.15, "\(format): \(duration)")
        }
    }

    @Test("A size target keeps the file under the limit", arguments: [OutputFormat.mp4, .webm])
    func sizeTarget(format: OutputFormat) async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let movie = try await fixtures.writeMovie("Big.mov", width: 1280, height: 720, seconds: 4)
        var settings = ConversionSettings(format: format)
        settings.video.quality = .maximum
        settings.video.targetMegabytes = 1
        let out = fixtures.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let result = try await ConversionService(tools: testTools).convert(movie, info: try await MediaProbe.probe(movie, tools: testTools),
                                                                           settings: settings, into: out)
        let bytes = try result.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max
        #expect(bytes <= 1_100_000, "\(format): \(bytes) bytes")
    }
}
