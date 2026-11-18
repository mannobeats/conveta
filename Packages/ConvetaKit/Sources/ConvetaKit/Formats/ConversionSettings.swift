import Foundation

/// Everything that decides how one file is converted. Small, value-typed and `Codable`,
/// so it can be stored as a default, sent from the Finder extension, or shown in the inspector.
public struct ConversionSettings: Codable, Sendable, Hashable {
    public var format: OutputFormat
    public var video = VideoOptions()
    public var audio = AudioOptions()
    public var image = ImageOptions()
    public var animation = AnimationOptions()
    public var document = DocumentOptions()
    /// For downloads: the exact picture height to fetch; `nil` takes the best on offer.
    public var downloadHeight: Int?

    public init(format: OutputFormat) {
        self.format = format
    }
}

// MARK: - Video

public enum VideoCodec: String, Codable, Sendable, CaseIterable, Identifiable {
    case h264, hevc, proRes422, proRes4444
    /// Copies the original streams without re-encoding. Instant, but ignores size and frame rate.
    case passthrough

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC (H.265)"
        case .proRes422: "ProRes 422"
        case .proRes4444: "ProRes 4444"
        case .passthrough: "Keep Original"
        }
    }

    public var summary: String {
        switch self {
        case .h264: "Most compatible"
        case .hevc: "Half the size, same quality"
        case .proRes422: "Editing, very large files"
        case .proRes4444: "Editing with transparency"
        case .passthrough: "No re-encoding, instant"
        }
    }

    /// ProRes has a fixed data rate, so the quality setting does not apply.
    public var usesQuality: Bool { self == .h264 || self == .hevc }
}

/// How hard the encoder works to keep detail. Mapped to a data rate per pixel.
public enum Quality: String, Codable, Sendable, CaseIterable, Identifiable {
    case compact, balanced, high, maximum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compact: "Compact"
        case .balanced: "Balanced"
        case .high: "High"
        case .maximum: "Maximum"
        }
    }

    /// Bits per pixel per frame for H.264. HEVC needs about 60 % of this.
    var bitsPerPixel: Double {
        switch self {
        case .compact: 0.045
        case .balanced: 0.075
        case .high: 0.12
        case .maximum: 0.2
        }
    }

    /// Lossy image quality (0...1) for JPEG, HEIC and AVIF.
    public var imageCompression: Double {
        switch self {
        case .compact: 0.6
        case .balanced: 0.78
        case .high: 0.9
        case .maximum: 1.0
        }
    }
}

/// Limits the shorter side of the picture. Never upscales.
public enum Resolution: Int, Codable, Sendable, CaseIterable, Identifiable {
    case original = 0
    case p2160 = 2160
    case p1440 = 1440
    case p1080 = 1080
    case p720 = 720
    case p480 = 480

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .original: "Original"
        case .p2160: "4K (2160p)"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }
}

public enum FrameRate: Int, Codable, Sendable, CaseIterable, Identifiable {
    case original = 0
    case fps24 = 24
    case fps25 = 25
    case fps30 = 30
    case fps60 = 60

    public var id: Int { rawValue }
    public var displayName: String { self == .original ? "Original" : "\(rawValue) fps" }
}

public struct VideoOptions: Codable, Sendable, Hashable {
    public var codec: VideoCodec = .h264
    public var quality: Quality = .balanced
    public var resolution: Resolution = .original
    public var frameRate: FrameRate = .original
    public var includeAudio = true
    public init() {}
}

// MARK: - Audio

public enum AudioCodec: String, Codable, Sendable, CaseIterable, Identifiable {
    case aac, alac
    public var id: String { rawValue }
    public var displayName: String { self == .aac ? "AAC" : "Apple Lossless" }
}

public enum SampleRate: Int, Codable, Sendable, CaseIterable, Identifiable {
    case original = 0
    case hz44100 = 44100
    case hz48000 = 48000
    case hz96000 = 96000

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .original: "Original"
        case .hz44100: "44.1 kHz"
        case .hz48000: "48 kHz"
        case .hz96000: "96 kHz"
        }
    }
}

public enum ChannelLayout: String, Codable, Sendable, CaseIterable, Identifiable {
    case original, stereo, mono
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum BitDepth: Int, Codable, Sendable, CaseIterable, Identifiable {
    case bits16 = 16
    case bits24 = 24
    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue)-bit" }
}

public struct AudioOptions: Codable, Sendable, Hashable {
    /// The codec inside an `.m4a`.
    public var codec: AudioCodec = .aac
    /// Data rate for AAC and Opus, in kbit/s.
    public var bitrate = 256
    public var sampleRate: SampleRate = .original
    public var channels: ChannelLayout = .original
    /// Sample size for WAV, AIFF, FLAC and Apple Lossless.
    public var bitDepth: BitDepth = .bits16
    public init() {}

    public static let bitrates = [64, 96, 128, 160, 192, 256, 320]
}

// MARK: - Image

public struct ImageOptions: Codable, Sendable, Hashable {
    public var quality: Quality = .high
    /// Longest side in pixels; `nil` keeps the original size. Never upscales.
    public var maxDimension: Int?
    /// Removes location, camera and other metadata.
    public var stripMetadata = false
    public init() {}

    public static let dimensionChoices = [4096, 3840, 2560, 2048, 1920, 1280, 1024, 800, 512]
}

// MARK: - GIF

public struct AnimationOptions: Codable, Sendable, Hashable {
    public var framesPerSecond = 15
    /// Width in pixels; `nil` keeps the source width (still capped at 1280).
    public var width: Int? = 480
    public var loops = true
    public init() {}

    public static let frameRates = [8, 10, 12, 15, 20, 24, 30]
    public static let widths = [240, 320, 480, 640, 800, 1080]
    public static let widthCap = 1280
}

// MARK: - PDF pages

public struct DocumentOptions: Codable, Sendable, Hashable {
    public var dotsPerInch = 150
    public init() {}

    public static let resolutions = [72, 150, 300, 600]
}
