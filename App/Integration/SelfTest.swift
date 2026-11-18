import AVFoundation
import AppKit
import ConvetaKit
import ImageIO
import UniformTypeIdentifiers

/// `Conveta --selftest`: runs the functions the UI calls, inside the real sandboxed app, against a
/// throwaway folder and throwaway preferences. Prints PASS or FAIL per step and exits 0 or 1.
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }

    static func run() {
        Task {
            let passed = await Runner().run()
            print(passed ? "SELFTEST PASSED" : "SELFTEST FAILED")
            exit(passed ? 0 : 1)
        }
    }
}

private final class Runner {
    private var failures = 0
    private let folder = FileManager.default.temporaryDirectory.appending(path: "ConvetaSelfTest-\(UUID().uuidString)", directoryHint: .isDirectory)
    private let store = UserDefaults(suiteName: "ConvetaSelfTest-\(UUID().uuidString)")!

    func run() async -> Bool {
        setbuf(stdout, nil)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try await steps()
        } catch {
            check("setup", false, "\(error)")
        }
        return failures == 0
    }

    private func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        print(condition ? "PASS" : "FAIL", name, condition ? "" : detail())
        if !condition { failures += 1 }
    }

    private func steps() async throws {
        let png = try writeImage("Photo.png")
        let wav = try writeTone("Tone.wav")
        let text = folder.appending(path: "Notes.txt")
        try Data("hello".utf8).write(to: text)

        let state = AppState(store: store)
        let queue = state.queue
        state.preferences.playSoundWhenDone = false
        state.preferences.notifyWhenDone = false

        // Shortcuts' format list mirrors the core's.
        check("intent formats mirror output formats",
              IntentFormat.allCases.map(\.rawValue) == OutputFormat.allCases.map(\.rawValue))

        // Adding reads every file; unsupported files say why.
        queue.add([png, wav, text])
        try await waitUntil("files are read") { !queue.jobs.contains { $0.state == .probing } }
        check("three rows added", queue.jobs.count == 3, "\(queue.jobs.count)")
        check("image ready as JPEG", queue.jobs.first { $0.kind == .image }?.settings.format == .jpeg)
        check("text file unsupported", queue.jobs.first { $0.source == text }?.state.isUnsupported == true)
        queue.add([png])
        check("duplicates are skipped", queue.jobs.count == 3)

        // Inspector edits apply per kind and are remembered.
        queue.updateSettings(kind: .image) { $0.format = .png }
        queue.updateSettings(kind: .audio) { $0.format = .flac }
        check("image set to PNG", queue.jobs.first { $0.kind == .image }?.settings.format == .png)
        check("audio set to FLAC", queue.jobs.first { $0.kind == .audio }?.settings.format == .flac)
        check("choice remembered", state.preferences.settings(for: .image).format == .png)

        // Convert twice in a row (menu and URL at once): each file is converted exactly once.
        queue.convertSelectionOrAll()
        queue.convertSelectionOrAll()
        try await waitUntil("batch finishes", seconds: 30) { !queue.isRunning }
        let outputs = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        check("each file converted once", Set(outputs) == ["Notes.txt", "Photo.png", "Photo 2.png", "Tone.flac", "Tone.wav"] && outputs.count == 5, "\(outputs)")
        check("jobs done", queue.jobs.filter { $0.state == .done }.count == 2)
        check("output sizes known", queue.finishedJobs.allSatisfy { ($0.outputSize ?? 0) > 0 })
        check("no working folders left", !outputs.contains { $0.hasPrefix(".conveta-") })

        // Clearing removes finished and unsupported rows.
        queue.clearFinished()
        check("clear finished empties the list", queue.jobs.isEmpty, "\(queue.jobs.map(\.name))")

        // The bundled FFmpeg helper runs inside the sandbox: MP3 and WebP out.
        check("FFmpeg helper bundled", FFmpegTools.bundled() != nil)
        queue.add([wav, png])
        try await waitUntil("files read again") { queue.jobs.count == 2 && !queue.jobs.contains { $0.state == .probing } }
        queue.updateSettings(kind: .audio) { $0.format = .mp3 }
        queue.updateSettings(kind: .image) { $0.format = .webp }
        queue.convertSelectionOrAll()
        try await waitUntil("FFmpeg batch finishes", seconds: 30) { !queue.isRunning }
        let failures = queue.jobs.compactMap { if case .failed(let reason) = $0.state { reason } else { nil } }
        check("MP3 and WebP converted in the sandbox", queue.jobs.allSatisfy { $0.state == .done }, failures.joined(separator: "; "))
        check("MP3 written", FileManager.default.fileExists(atPath: folder.appending(path: "Tone.mp3").path))
        check("WebP written", FileManager.default.fileExists(atPath: folder.appending(path: "Photo.webp").path))
        queue.clearFinished()

        // Cancelling stops a running job and leaves no file.
        let longTone = try writeTone("Long.wav", seconds: 600)
        queue.add([longTone])
        try await waitUntil("long file read") { queue.jobs.first?.state == .ready }
        queue.updateSettings { $0.format = .mp3 }
        queue.convertSelectionOrAll()
        try await waitUntil("conversion starts") { queue.jobs.first?.state == .converting }
        queue.cancelAll()
        try await waitUntil("cancel lands") { !queue.isRunning }
        check("cancelled state", queue.jobs.first?.state == .cancelled, "\(String(describing: queue.jobs.first?.state))")
        check("no partial output", !FileManager.default.fileExists(atPath: folder.appending(path: "Long.mp3").path))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasPrefix(".conveta-") } ?? []
        check("no working folders after cancel", leftovers.isEmpty, "\(leftovers)")

        // Hand-offs from Finder go through the shared app group.
        let request = HandoffRequest(paths: [png.path], format: .heic)
        AppGroup.handoffs.save(request)
        check("app group hand-off round trip", AppGroup.handoffs.take(request.id) == request)
        check("hand-off URL parses", HandoffStore.requestID(in: HandoffStore.url(for: request)) == request.id)

        check("common ancestor", FolderAccess.commonAncestor(of: [URL(filePath: "/Users/a/Movies/x"), URL(filePath: "/Users/a/Desktop")])?.path == "/Users/a")
        check("every SF Symbol exists", MediaKind.allCases.allSatisfy { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil) != nil })
    }

    private func waitUntil(_ name: String, seconds: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(seconds)
        while !condition() {
            guard Date.now < deadline else {
                check(name, false, "timed out")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func writeImage(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    private func writeTone(_ name: String, seconds: Double = 1) throws -> URL {
        let url = folder.appending(path: name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                                                              AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = 0.3 * sin(Float(i) * 0.06) }
        }
        try file.write(from: buffer)
        return url
    }
}
