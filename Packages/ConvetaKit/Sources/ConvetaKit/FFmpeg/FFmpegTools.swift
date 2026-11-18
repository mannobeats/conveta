import Foundation
import os

/// The bundled `ffmpeg` and `ffprobe` executables. Conveta uses them only for what Apple's
/// frameworks can't do: writing MP3, MKV, WebM, Ogg, WMA and WebP, and reading files such as
/// MKV, WebM, FLV, WMA, Ogg Vorbis or APE.
public struct FFmpegTools: Sendable, Equatable {
    public let ffmpeg: URL
    public let ffprobe: URL

    public init(ffmpeg: URL, ffprobe: URL) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }

    /// The helpers inside an app bundle's `Contents/Helpers`, if both are there.
    public static func bundled(in bundle: Bundle = .main) -> FFmpegTools? {
        let helpers = bundle.bundleURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory)
        return tools(in: helpers)
    }

    /// Both tools from `folder`, if both exist and are executable.
    public static func tools(in folder: URL) -> FFmpegTools? {
        let tools = FFmpegTools(ffmpeg: folder.appending(path: "ffmpeg"), ffprobe: folder.appending(path: "ffprobe"))
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: tools.ffmpeg.path), manager.isExecutableFile(atPath: tools.ffprobe.path) else { return nil }
        return tools
    }
}

/// Runs a command-line tool, streaming progress and honouring task cancellation.
enum ToolRunner {
    struct Failure: Error {
        let status: Int32
        let message: String
    }

    /// Runs `tool` and returns its standard output. Each stdout line is passed to `onLine` as it arrives.
    /// Cancelling the task terminates the process.
    @discardableResult
    static func run(_ tool: URL, _ arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let collected = OSAllocatedUnfairLock(initialState: (out: Data(), err: Data()))
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collected.withLock { $0.out.append(chunk) }
            if let onLine { String(decoding: chunk, as: UTF8.self).split(whereSeparator: \.isNewline).forEach { onLine(String($0)) } }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collected.withLock { state in
                state.err.append(chunk)
                if state.err.count > 16_384 { state.err = state.err.suffix(8_192) }
            }
        }

        // Cancellation can arrive before the process starts; only a running process may be terminated.
        enum Phase { case waiting, running, cancelled }
        let phase = OSAllocatedUnfairLock(initialState: Phase.waiting)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
                let started: Result<Void, Error> = phase.withLock { current in
                    guard current == .waiting else { return .failure(CancellationError()) }
                    do {
                        try process.run()
                        current = .running
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
                if case .failure(let error) = started {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            phase.withLock { current in
                if current == .running { process.terminate() }
                current = .cancelled
            }
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        let rest = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        let restErrors = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
        let (out, err) = collected.withLock { ($0.out + rest, $0.err + restErrors) }

        try Task.checkCancellation()
        guard status == 0 else {
            let lines = String(decoding: err, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
            throw Failure(status: status, message: lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "exit \(status)")
        }
        return String(decoding: out, as: UTF8.self)
    }
}
