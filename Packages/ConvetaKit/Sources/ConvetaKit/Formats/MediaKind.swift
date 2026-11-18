import Foundation
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

    /// The kind of a file, from its content type or, for types macOS doesn't know, its extension.
    public init?(url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        if let type, let kind = MediaKind(contentType: type) {
            self = kind
        } else if let kind = Self.byExtension[url.pathExtension.lowercased()] {
            self = kind
        } else {
            return nil
        }
    }

    /// Media extensions macOS may not declare a type for (they are read through FFmpeg).
    static let byExtension: [String: MediaKind] = {
        var map: [String: MediaKind] = [:]
        for ext in ["mkv", "webm", "avi", "wmv", "flv", "f4v", "mpg", "mpeg", "m2v", "ts", "mts", "m2ts", "vob",
                    "ogv", "3gp", "3g2", "asf", "rm", "rmvb", "divx", "mxf", "nut", "y4m", "dv"] { map[ext] = .video }
        for ext in ["mp3", "wav", "aac", "m4a", "flac", "ogg", "oga", "opus", "wma", "aiff", "aif", "ape", "wv",
                    "amr", "ac3", "eac3", "dts", "mka", "caf", "mp2", "au", "tta", "spx", "mpc", "w64", "voc"] { map[ext] = .audio }
        for ext in ["webp", "jxl", "avif", "heic", "heif", "jp2", "tga", "exr", "dds", "psd"] { map[ext] = .image }
        return map
    }()

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
        case .video: [.mp4, .mov, .m4v, .mkv, .webm, .avi, .gif, .mp3, .m4a, .aac, .wav, .aiff, .flac, .ogg, .opus, .wma]
        case .audio: [.mp3, .m4a, .aac, .wav, .aiff, .flac, .ogg, .opus, .wma]
        case .image: [.jpeg, .png, .heic, .avif, .webp, .tiff, .gif, .bmp, .pdf]
        case .document: [.png, .jpeg, .heic, .tiff]
        }
    }

    /// The format offered first for a new file of this kind.
    public var defaultFormat: OutputFormat {
        switch self {
        case .video: .mp4
        case .audio: .mp3
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
