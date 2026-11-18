import Foundation
import os

/// Reports progress from 0 to 1. Called from a background thread, at most about 100 times per job.
public typealias ProgressHandler = @Sendable (Double) -> Void

/// One conversion: read `source`, write `destination`.
/// The destination is a working path; ``ConversionService`` moves it into place when the converter returns.
public struct ConversionRequest: Sendable {
    public var source: URL
    public var destination: URL
    public var settings: ConversionSettings
    public var info: MediaInfo

    public init(source: URL, destination: URL, settings: ConversionSettings, info: MediaInfo) {
        self.source = source
        self.destination = destination
        self.settings = settings
        self.info = info
    }
}

/// What a converter wrote: a single file, or a folder of files (one per PDF page).
public enum ConversionOutput: Sendable, Equatable {
    case file
    case folder(count: Int)
}

/// A converter turns one source into one output. Implementations are stateless.
protocol Converter: Sendable {
    func convert(_ request: ConversionRequest, progress: @escaping ProgressHandler) async throws -> ConversionOutput
}

public enum ConversionError: LocalizedError, Equatable {
    case unsupportedConversion(from: MediaKind, to: OutputFormat)
    case unreadable
    case noVideoTrack
    case noAudioTrack
    case encoderUnavailable(String)
    case failed(String)
    case noWriteAccess(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedConversion(let kind, let format):
            "\(kind.displayName) files can’t be converted to \(format.displayName)."
        case .unreadable: "The file couldn’t be read. It may be damaged or protected."
        case .noVideoTrack: "This file has no video."
        case .noAudioTrack: "This file has no audio."
        case .encoderUnavailable(let name): "This Mac can’t encode \(name)."
        case .failed(let reason): reason
        case .noWriteAccess(let folder): "Conveta isn’t allowed to save in “\(folder.lastPathComponent)”."
        }
    }
}

/// Calls a progress handler only when the value moved by at least half a percent.
final class ProgressThrottle: Sendable {
    private let handler: ProgressHandler
    private let last = OSAllocatedUnfairLock(initialState: -1.0)

    init(_ handler: @escaping ProgressHandler) { self.handler = handler }

    func report(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        let shouldSend = last.withLock { last in
            guard clamped - last >= 0.005 || (clamped == 1 && last < 1) else { return false }
            last = clamped
            return true
        }
        if shouldSend { handler(clamped) }
    }
}
