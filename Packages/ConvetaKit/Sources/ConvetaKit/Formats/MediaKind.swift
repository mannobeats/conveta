import UniformTypeIdentifiers

/// The family a source file belongs to. Decides which output formats it can become.
public enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case video
    case audio
    case image
    case document

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Image"
        case .document: "PDF"
        }
    }

    /// SF Symbol used everywhere this kind is shown.
    public var symbolName: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .document: "doc.richtext"
        }
    }

    /// The kind a content type belongs to, judged by its declared type alone.
    /// Probing (``MediaProbe``) refines this, for example an audio-only `.mp4`.
    public init?(contentType type: UTType) {
        if type.conforms(to: .pdf) {
            self = .document
        } else if type.conforms(to: .audio) {
            self = .audio
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            self = .video
        } else if type.conforms(to: .image) {
            self = .image
        } else {
            return nil
        }
    }

    /// Output formats this kind can be converted to, in the order they are offered.
    public var outputFormats: [OutputFormat] {
        switch self {
        case .video: [.mp4, .mov, .m4v, .gif, .m4a, .wav, .aiff, .flac, .opus]
        case .audio: [.m4a, .wav, .aiff, .flac, .opus]
        case .image: [.jpeg, .png, .heic, .avif, .tiff, .gif, .bmp, .pdf]
        case .document: [.png, .jpeg, .heic, .tiff]
        }
    }

    /// The format offered first for a new file of this kind.
    public var defaultFormat: OutputFormat {
        switch self {
        case .video: .mp4
        case .audio: .m4a
        case .image: .jpeg
        case .document: .png
        }
    }

    /// Formats every one of `kinds` can become, in the first kind's order.
    public static func commonFormats(for kinds: some Collection<MediaKind>) -> [OutputFormat] {
        guard let first = kinds.first else { return [] }
        return first.outputFormats.filter { format in kinds.allSatisfy { $0.outputFormats.contains(format) } }
    }
}
