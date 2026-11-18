import AppKit
import ConvetaKit
import Foundation
import Observation

/// One file in the queue: what it is, how it will be converted, and how far it got.
@Observable
final class ConversionJob: Identifiable {
    enum State: Equatable {
        case probing
        case ready
        case queued
        case converting
        case done
        case failed(String)
        case cancelled
        case unsupported(String)

        var isActive: Bool { self == .queued || self == .converting }
        var isFinished: Bool { self == .done }
        /// The job can be (re)started.
        var isStartable: Bool {
            switch self {
            case .ready, .failed, .cancelled: true
            default: false
            }
        }
        /// Its settings can still change.
        var isEditable: Bool { isStartable }
    }

    let id = UUID()
    /// A file on disk, or the web link of a download.
    let source: URL
    /// What the link points to, once read. `nil` for files.
    var remote: RemoteMedia?
    var info: MediaInfo?
    var settings: ConversionSettings
    var state: State = .probing
    var progress = 0.0
    var output: URL?
    var outputSize: Int64?
    var thumbnail: NSImage?
    var startedAt: Date?
    var finishedAt: Date?

    init(source: URL, settings: ConversionSettings) {
        self.source = source
        self.settings = settings
    }

    var isDownload: Bool { !source.isFileURL }
    var name: String {
        if let remote { return remote.title }
        return isDownload ? (source.host() ?? "") + source.path() : source.lastPathComponent
    }
    var kind: MediaKind? { info?.kind }

    /// Output size as a share of the input, for example -0.67 for a file a third the size.
    var sizeChange: Double? {
        guard !isDownload, let outputSize, let input = info?.fileSize, input > 0 else { return nil }
        return Double(outputSize) / Double(input) - 1
    }
}
