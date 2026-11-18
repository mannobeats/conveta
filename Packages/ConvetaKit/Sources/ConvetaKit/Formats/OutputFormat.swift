import UniformTypeIdentifiers

/// A file format Conveta writes. Each one is produced by Apple's own frameworks,
/// so conversions are hardware accelerated where the Mac allows it.
public enum OutputFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    // Video
    case mp4, mov, m4v
    // Animated image
    case gif
    // Audio
    case m4a, wav, aiff, flac, opus
    // Still image
    case jpeg, png, heic, avif, tiff, bmp, pdf

    public var id: String { rawValue }

    /// The family of the file this format produces.
    public var kind: MediaKind {
        switch self {
        case .mp4, .mov, .m4v: .video
        case .m4a, .wav, .aiff, .flac, .opus: .audio
        case .gif, .jpeg, .png, .heic, .avif, .tiff, .bmp: .image
        case .pdf: .document
        }
    }

    public var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .mov: "MOV"
        case .m4v: "M4V"
        case .gif: "GIF"
        case .m4a: "M4A"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .flac: "FLAC"
        case .opus: "Opus"
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .avif: "AVIF"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .pdf: "PDF"
        }
    }

    /// One short line that helps people choose.
    public var summary: String {
        switch self {
        case .mp4: "Plays everywhere"
        case .mov: "Apple and editing apps"
        case .m4v: "Apple TV and iTunes"
        case .gif: "Short looping animation"
        case .m4a: "Small, great quality"
        case .wav: "Uncompressed, universal"
        case .aiff: "Uncompressed, Apple"
        case .flac: "Lossless, open"
        case .opus: "Smallest for voice and music"
        case .jpeg: "Photos, universal"
        case .png: "Lossless, keeps transparency"
        case .heic: "Half the size of JPEG"
        case .avif: "Smallest for the web"
        case .tiff: "Lossless, for print"
        case .bmp: "Uncompressed bitmap"
        case .pdf: "Document, prints anywhere"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .aiff: "aiff"
        default: rawValue
        }
    }

    public var contentType: UTType {
        switch self {
        case .mp4: .mpeg4Movie
        case .mov: .quickTimeMovie
        case .m4v: UTType("com.apple.m4v-video") ?? .mpeg4Movie
        case .gif: .gif
        case .m4a: .mpeg4Audio
        case .wav: .wav
        case .aiff: .aiff
        case .flac: UTType("org.xiph.flac") ?? .audio
        case .opus: UTType(filenameExtension: "opus") ?? .audio
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .avif: UTType("public.avif") ?? .image
        case .tiff: .tiff
        case .bmp: .bmp
        case .pdf: .pdf
        }
    }

    /// Whether the encoder discards information. Lossy formats expose a quality setting.
    public var isLossy: Bool {
        switch self {
        case .jpeg, .heic, .avif, .m4a, .opus, .mp4, .mov, .m4v, .gif: true
        case .png, .tiff, .bmp, .pdf, .wav, .aiff, .flac: false
        }
    }

    /// Whether the format can store an alpha channel.
    public var supportsTransparency: Bool {
        switch self {
        case .png, .heic, .avif, .tiff, .gif, .pdf: true
        default: false
        }
    }

    /// Video containers accept these codecs.
    public var videoCodecs: [VideoCodec] {
        switch self {
        case .mov: [.h264, .hevc, .proRes422, .proRes4444, .passthrough]
        case .mp4, .m4v: [.h264, .hevc, .passthrough]
        default: []
        }
    }
}
