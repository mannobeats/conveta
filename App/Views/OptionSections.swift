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
        let codec = current.format.videoCodecs.contains(current.video.codec) ? current.video.codec : .h264
        Section {
            Picker("Codec", selection: bind(current, \.video.codec, update)) {
                ForEach(current.format.videoCodecs) { Text($0.displayName).tag($0) }
            }
            .help(codec.summary)
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
            Text(codec == .passthrough
                 ? "Copies the video without re-encoding: instant and lossless, but size and frame rate stay as they are. Falls back to H.264 when the codec doesn’t fit this format."
                 : "\(codec.summary). Encoded with the Mac’s media engine. Never upscales.")
                .foregroundStyle(.secondary)
        }
    }
}

struct AudioSection: View {
    let current: ConversionSettings
    let update: SettingsUpdate

    var body: some View {
        let format = current.format
        let lossless = format == .wav || format == .aiff || format == .flac || (format == .m4a && current.audio.codec == .alac)
        let compressed = format == .opus || (format == .m4a && current.audio.codec == .aac)
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
            Text(footer(lossless: lossless))
                .foregroundStyle(.secondary)
        }
    }

    private func footer(lossless: Bool) -> String {
        if current.format == .opus { return "Opus always plays at 48 kHz. 96–128 kbit/s is transparent for most music." }
        if lossless { return "Lossless: every sample is kept. Surround sound is mixed down to stereo." }
        return "256 kbit/s AAC is what Apple Music uses. AAC tops out at 48 kHz."
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
