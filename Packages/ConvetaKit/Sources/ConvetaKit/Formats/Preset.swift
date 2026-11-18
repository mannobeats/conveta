import Foundation

/// A named recipe: a format and its options, for files of the kinds it suits.
/// Conveta ships a few; people save their own from the inspector.
public struct Preset: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// One short line: what it's for.
    public var summary: String
    public var settings: ConversionSettings
    public var isBuiltIn: Bool

    public init(id: String = UUID().uuidString, name: String, summary: String, settings: ConversionSettings, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.summary = summary
        self.settings = settings
        self.isBuiltIn = isBuiltIn
    }

    /// Whether a file of `kind` can use this preset.
    public func applies(to kind: MediaKind) -> Bool {
        kind.outputFormats.contains(settings.format)
    }

    /// The presets that suit every one of `kinds`.
    public static func suiting(_ kinds: some Collection<MediaKind>, from presets: [Preset]) -> [Preset] {
        guard !kinds.isEmpty else { return [] }
        return presets.filter { preset in kinds.allSatisfy(preset.applies(to:)) }
    }

    /// Applies the preset to existing settings, keeping a download's chosen height and subtitles and any trim.
    public func apply(to current: ConversionSettings) -> ConversionSettings {
        var result = settings
        result.trim = current.trim
        result.downloadHeight = current.downloadHeight
        result.subtitles = current.subtitles
        return result
    }

    // MARK: Built in

    public static let builtIn: [Preset] = {
        func video(_ id: String, _ name: String, _ summary: String, megabytes: Int? = nil, resolution: Resolution, fps: FrameRate = .original,
                   codec: VideoCodec = .h264) -> Preset {
            var settings = ConversionSettings(format: .mp4)
            settings.video.codec = codec
            settings.video.resolution = resolution
            settings.video.frameRate = fps
            settings.video.targetMegabytes = megabytes
            settings.video.quality = .high
            return Preset(id: id, name: name, summary: summary, settings: settings, isBuiltIn: true)
        }
        var podcast = ConversionSettings(format: .mp3)
        podcast.audio.bitrate = 96
        podcast.audio.channels = .mono
        var music = ConversionSettings(format: .m4a)
        music.audio.bitrate = 256
        var archive = ConversionSettings(format: .flac)
        archive.audio.bitDepth = .bits24
        var web = ConversionSettings(format: .webp)
        web.image.maxDimension = 1920
        web.image.quality = .high
        web.image.stripMetadata = true
        var share = ConversionSettings(format: .jpeg)
        share.image.maxDimension = 2048
        share.image.stripMetadata = true
        var gif = ConversionSettings(format: .gif)
        gif.animation.width = 480
        gif.animation.framesPerSecond = 15

        return [
            video("discord", "Discord", "Fits the 10 MB upload limit", megabytes: 10, resolution: .p720, fps: .fps30),
            video("email", "Email", "Under 25 MB, for attachments", megabytes: 25, resolution: .p720),
            video("whatsapp", "WhatsApp", "720p, small and quick to send", megabytes: 64, resolution: .p720, fps: .fps30),
            video("social", "Instagram & TikTok", "1080p H.264, what they recommend", resolution: .p1080, fps: .fps30),
            video("archive-video", "Smaller, Same Quality", "HEVC at full size, about half the space", resolution: .original, codec: .hevc),
            Preset(id: "gif", name: "GIF for Messages", summary: "480 px at 15 fps", settings: gif, isBuiltIn: true),
            Preset(id: "podcast", name: "Podcast", summary: "MP3, mono, 96 kbit/s", settings: podcast, isBuiltIn: true),
            Preset(id: "music", name: "Apple Music Quality", summary: "AAC at 256 kbit/s", settings: music, isBuiltIn: true),
            Preset(id: "lossless", name: "Lossless Archive", summary: "FLAC, 24-bit", settings: archive, isBuiltIn: true),
            Preset(id: "web-images", name: "Web Images", summary: "WebP, 1920 px, no location", settings: web, isBuiltIn: true),
            Preset(id: "share-photos", name: "Share Photos", summary: "JPEG, 2048 px, no location", settings: share, isBuiltIn: true),
        ]
    }()
}

/// Built-in presets plus the person's own, kept where the Finder extension can read them too.
public struct PresetStore: Sendable {
    static let key = "customPresets"
    private let suiteName: String?

    public init(suiteName: String?) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public var custom: [Preset] {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? []
    }

    public var all: [Preset] { custom + Preset.builtIn }

    public func preset(id: String) -> Preset? { all.first { $0.id == id } }

    public func save(_ preset: Preset) {
        var list = custom.filter { $0.id != preset.id }
        list.insert(preset, at: 0)
        defaults.set(try? JSONEncoder().encode(list), forKey: Self.key)
    }

    public func delete(_ id: String) {
        defaults.set(try? JSONEncoder().encode(custom.filter { $0.id != id }), forKey: Self.key)
    }
}
