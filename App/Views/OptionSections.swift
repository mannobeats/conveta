import ConvetaKit
import SwiftUI

typealias SettingsUpdate = ((inout ConversionSettings) -> Void) -> Void

/// A binding to one setting that writes to every edited file.
private func bind<Value>(_ current: ConversionSettings, _ key: WritableKeyPath<ConversionSettings, Value>,
                         _ update: @escaping SettingsUpdate) -> Binding<Value> {
    Binding(get: { current[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } })
}

struct VideoSection: View {
    let current: ConversionSettings
    let update: SettingsUpdate

    var body: some View {
        let codecs = current.format.videoCodecs
        // WebM and AVI each have one codec, so there is nothing to choose.
        let codec = codecs.isEmpty ? .h264 : (codecs.contains(current.video.codec) ? current.video.codec : .h264)
        Section {
            if !codecs.isEmpty {
                Picker("Codec", selection: bind(current, \.video.codec, update)) {
                    ForEach(codecs) { Text($0.displayName).tag($0) }
                }
                .help(codec.summary)
            }
            if codec.usesQuality {
                Picker("Quality", selection: bind(current, \.video.quality, update)) {
                    ForEach(Quality.allCases) { Text($0.displayName).tag($0) }
                }
            }
            if codec != .passthrough {
                Picker("Resolution", selection: bind(current, \.video.resolution, update)) {
                    ForEach(Resolution.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Frame Rate", selection: bind(current, \.video.frameRate, update)) {
                    ForEach(FrameRate.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Toggle("Include Audio", isOn: bind(current, \.video.includeAudio, update))
        } header: {
            Text("Video Options")
        } footer: {
            Text(footer(codec: codec))
                .foregroundStyle(.secondary)
        }
    }
}

extension VideoSection {
    private func footer(codec: VideoCodec) -> String {
        switch current.format {
        case .webm: return "VP9 video with Opus sound, for browsers and the web. Never upscales."
        case .avi: return "MPEG-4 video with MP3 sound, for older players and TVs. Never upscales."
        default:
            return codec == .passthrough
                ? "Copies the video without re-encoding: instant and lossless, but size and frame rate stay as they are. Falls back to H.264 when the codec doesn’t fit this format."
                : "\(codec.summary). Encoded with the Mac’s media engine. Never upscales."
        }
    }
}

struct AudioSection: View {
    let current: ConversionSettings
    let update: SettingsUpdate

    var body: some View {
        let format = current.format
        let lossless = format == .wav || format == .aiff || format == .flac || (format == .m4a && current.audio.codec == .alac)
        let compressed = [.opus, .mp3, .aac, .ogg, .wma].contains(format) || (format == .m4a && current.audio.codec == .aac)
        Section {
            if format == .m4a {
                Picker("Codec", selection: bind(current, \.audio.codec, update)) {
                    ForEach(AudioCodec.allCases) { Text($0.displayName).tag($0) }
                }
            }
            if compressed {
                Picker("Bitrate", selection: bind(current, \.audio.bitrate, update)) {
                    ForEach(AudioOptions.bitrates, id: \.self) { Text("\($0) kbit/s").tag($0) }
                }
            }
            if lossless {
                Picker("Bit Depth", selection: bind(current, \.audio.bitDepth, update)) {
                    ForEach(BitDepth.allCases) { Text($0.displayName).tag($0) }
                }
            }
            if format != .opus {
                Picker("Sample Rate", selection: bind(current, \.audio.sampleRate, update)) {
                    ForEach(SampleRate.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Picker("Channels", selection: bind(current, \.audio.channels, update)) {
                ForEach(ChannelLayout.allCases) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Audio Options")
        } footer: {
            Text(compressed ? footer(lossless: lossless) + " Never encodes above the original’s bitrate." : footer(lossless: lossless))
                .foregroundStyle(.secondary)
        }
    }

    private func footer(lossless: Bool) -> String {
        switch current.format {
        case .opus: return "Opus always plays at 48 kHz. 96–128 kbit/s is transparent for most music."
        case .mp3: return "320 kbit/s is the best MP3 can do; 192 kbit/s suits most listening."
        case .ogg: return "Vorbis in an Ogg file, common in games and Linux apps."
        case .wma: return "Windows Media Audio, up to 192 kbit/s, for older Windows players."
        default:
            if lossless { return "Lossless: every sample is kept. Converting from MP3 or AAC can’t restore detail, and files get much larger." }
            return "256 kbit/s AAC is what Apple Music uses. AAC tops out at 48 kHz."
        }
    }
}

struct ImageSection: View {
    let current: ConversionSettings
    let update: SettingsUpdate

    var body: some View {
        let format = current.format
        Section {
            if format.isLossy, format != .gif {
                Picker("Quality", selection: bind(current, \.image.quality, update)) {
                    ForEach(Quality.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Picker("Size", selection: bind(current, \.image.maxDimension, update)) {
                Text("Original").tag(Int?.none)
                Divider()
                ForEach(ImageOptions.dimensionChoices, id: \.self) { Text("Up to \($0) px").tag(Int?.some($0)) }
            }
            Toggle("Remove Location and Camera Info", isOn: bind(current, \.image.stripMetadata, update))
        } header: {
            Text("Image Options")
        } footer: {
            Text(format.supportsTransparency || format == .pdf
                 ? "Size limits the longest side and never enlarges."
                 : "\(format.displayName) has no transparency, so clear areas become white. Size limits the longest side.")
                .foregroundStyle(.secondary)
        }
    }
}

struct AnimationSection: View {
    let current: ConversionSettings
    let update: SettingsUpdate

    var body: some View {
        Section {
            Picker("Frame Rate", selection: bind(current, \.animation.framesPerSecond, update)) {
                ForEach(AnimationOptions.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            Picker("Width", selection: bind(current, \.animation.width, update)) {
                ForEach(AnimationOptions.widths, id: \.self) { Text("\($0) px").tag(Int?.some($0)) }
                Divider()
                Text("Original (up to \(AnimationOptions.widthCap) px)").tag(Int?.none)
            }
            Toggle("Loop Forever", isOn: bind(current, \.animation.loops, update))
        } header: {
            Text("Animation Options")
        } footer: {
            Text("GIFs grow quickly. 480 px at 15 fps suits most messages and docs.")
                .foregroundStyle(.secondary)
        }
    }
}

struct PageSection: View {
    let current: ConversionSettings
    let update: SettingsUpdate
    /// Hidden when the image section below already shows quality.
    let showsQuality: Bool

    var body: some View {
        Section {
            Picker("Resolution", selection: bind(current, \.document.dotsPerInch, update)) {
                ForEach(DocumentOptions.resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
            }
            if showsQuality, current.format.isLossy {
                Picker("Quality", selection: bind(current, \.image.quality, update)) {
                    ForEach(Quality.allCases) { Text($0.displayName).tag($0) }
                }
            }
        } header: {
            Text("PDF Pages")
        } footer: {
            Text("Each page becomes an image. PDFs with several pages get a folder of numbered pages.")
                .foregroundStyle(.secondary)
        }
    }
}
