import UniformTypeIdentifiers

/// A file format Conveta writes. Most are produced by Apple's own frameworks (hardware
/// accelerated where the Mac allows it); the rest by the bundled LGPL FFmpeg helper, see `isNative`.
public enum OutputFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    // Video
    case mp4, mov, m4v, mkv, webm, avi
    // Animated image
    case gif
    // Audio
    case mp3, m4a, aac, wav, aiff, flac, ogg, opus, wma
    // Still image
    case jpeg, png, heic, avif, webp, tiff, bmp, pdf

    public var id: String { rawValue }

    /// The family of the file this format produces.
    public var kind: MediaKind {
        switch self {
        case .mp4, .mov, .m4v, .mkv, .webm, .avi: .video
        case .mp3, .m4a, .aac, .wav, .aiff, .flac, .ogg, .opus, .wma: .audio
        case .gif, .jpeg, .png, .heic, .avif, .webp, .tiff, .bmp: .image
        case .pdf: .document
        }
    }

    public var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .mov: "MOV"
        case .m4v: "M4V"
        case .mkv: "MKV"
        case .webm: "WebM"
        case .avi: "AVI"
        case .gif: "GIF"
        case .mp3: "MP3"
        case .aac: "AAC"
        case .ogg: "Ogg"
        case .wma: "WMA"
        case .webp: "WebP"
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
        case .mkv: "Flexible, keeps every track"
        case .webm: "Open video for the web"
        case .avi: "Older players and devices"
        case .gif: "Short looping animation"
        case .mp3: "Plays on everything"
        case .aac: "Raw AAC stream"
        case .ogg: "Open, Vorbis audio"
        case .wma: "Windows Media players"
        case .webp: "Small images for the web"
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
        case .mkv: UTType(filenameExtension: "mkv") ?? .movie
        case .webm: UTType(filenameExtension: "webm") ?? .movie
        case .avi: .avi
        case .gif: .gif
        case .mp3: .mp3
        case .aac: UTType(filenameExtension: "aac") ?? .audio
        case .ogg: UTType(filenameExtension: "ogg") ?? .audio
        case .wma: UTType(filenameExtension: "wma") ?? .audio
        case .webp: .webP
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
        case .jpeg, .heic, .avif, .webp, .m4a, .opus, .mp3, .aac, .ogg, .wma,
             .mp4, .mov, .m4v, .mkv, .webm, .avi, .gif: true
        case .png, .tiff, .bmp, .pdf, .wav, .aiff, .flac: false
        }
    }

    /// Whether the format can store an alpha channel.
    public var supportsTransparency: Bool {
        switch self {
        case .png, .heic, .avif, .webp, .tiff, .gif, .pdf: true
        default: false
        }
    }

    /// Video containers accept these codecs.
    public var videoCodecs: [VideoCodec] {
        switch self {
        case .mov: [.h264, .hevc, .proRes422, .proRes4444, .passthrough]
        case .mkv: [.h264, .hevc, .proRes422, .passthrough]
        case .mp4, .m4v: [.h264, .hevc, .passthrough]
        default: []  // WebM is always VP9, AVI always MPEG-4 Part 2
        }
    }

    /// Formats Apple's frameworks write. The rest are written by the bundled FFmpeg helper.
    public var isNative: Bool {
        switch self {
        case .mkv, .webm, .avi, .mp3, .aac, .ogg, .wma, .webp: false
        default: true
        }
    }
}
