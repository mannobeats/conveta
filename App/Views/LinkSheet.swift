import AppKit
import ConvetaKit
import SwiftUI

/// "Download from a Link". Paste a link and the sheet reads it at once: a preview card, then every
/// resolution the video really has, with its size. Pick one or several; each becomes a download.
/// Several links at once get one quality limit for all of them.
struct LinkSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var format: OutputFormat = .mp4
    @State private var phase: Phase = .idle
    @State private var heights: Set<Int> = []
    @State private var batchLimit: Int? = 1080
    @State private var picked: Set<String> = []

    enum Phase: Equatable {
        case idle
        case reading
        case ready(RemoteMedia)
        case list(Playlist)
        case failed(String)
    }

    private var links: [URL] { LinkDetector.links(in: text) }
    private var media: RemoteMedia? { if case .ready(let media) = phase { media } else { nil } }
    private var playlist: Playlist? { if case .list(let list) = phase { list } else { nil } }
    private var audioOnly: Bool { format.kind == .audio || media?.hasVideo == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            field
            if links.count > 1 {
                BatchSummary(links: links, limit: $batchLimit, audioOnly: audioOnly)
            } else {
                preview
            }
            formatRow
            if !audioOnly { subtitleRow }
            footer
        }
        .padding(20)
        .frame(width: 560)
        .animation(Theme.motion, value: phase)
        .animation(Theme.motion, value: audioOnly)
        .onAppear(perform: prefill)
        .task(id: links.count == 1 ? links.first : nil) { await read() }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 12) {
            KindArtwork(kind: .video, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Download from a Link").font(.headline)
                Text("YouTube, Instagram, TikTok, X, Vimeo and more than a thousand other sites.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var field: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Paste a link, or several, one per line", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)  // grow with long or several links instead of clipping
                .textFieldStyle(.roundedBorder)
                .onSubmit(download)
            Button("Paste", systemImage: "doc.on.clipboard") {
                text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
            }
            .labelStyle(.iconOnly)
            .help("Paste from the clipboard")
        }
    }

    @ViewBuilder private var preview: some View {
        switch phase {
        case .idle:
            if !text.isEmpty, links.isEmpty {
                Label("That doesn’t look like a web link.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        case .reading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(state.downloader.status == .installing ? "Setting up downloads. This happens once." : "Reading link…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .transition(.opacity)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            PlaylistPanel(playlist: list, picked: $picked, limit: $batchLimit, audioOnly: audioOnly)
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .ready(let media):
            VStack(alignment: .leading, spacing: 14) {
                PreviewCard(media: media)
                if !audioOnly, !media.qualities.isEmpty {
                    QualityPicker(qualities: media.qualities, selection: $heights)
                    if converts(media) {
                        Label("1440p and 4K come from YouTube as VP9 or AV1, so Conveta converts them to HEVC after downloading. They then play in QuickTime and on every Apple device.",
                              systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var formatRow: some View {
        HStack(spacing: 8) {
            Text("Save as")
            Picker("Save as", selection: $format) {
                Section("Video") {
                    ForEach([OutputFormat.mp4, .mov, .mkv, .webm, .gif]) { Text($0.displayName).tag($0) }
                }
                Section("Audio only") {
                    ForEach([OutputFormat.mp3, .m4a, .wav, .flac, .opus]) { Text($0.displayName).tag($0) }
                }
            }
            .labelsHidden()
            .fixedSize()
            Text(format.summary).foregroundStyle(.secondary)
            Spacer()
        }
        .font(.callout)
    }

    private var subtitleRow: some View {
        @Bindable var preferences = state.preferences
        return HStack(spacing: 8) {
            Text("Subtitles")
            Picker("Subtitles", selection: $preferences.subtitles.mode) {
                ForEach(SubtitleOptions.Mode.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            if preferences.subtitles.mode != .off {
                Text(Locale.current.localizedString(forLanguageCode: preferences.subtitles.language) ?? preferences.subtitles.language)
                    .foregroundStyle(.secondary)
                    .help("Change the language in Settings → Downloads")
            }
            Spacer()
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text("Download only videos you own or have permission to use.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if let total = estimatedTotal {
                Text("About \(total.fileSizeText)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(downloadTitle, action: download)
                .keyboardShortcut(.defaultAction)
                .disabled(!canDownload)
        }
    }

    // MARK: Logic

    private var chosenHeights: [Int?] {
        guard let media, !audioOnly, !media.qualities.isEmpty else { return [nil] }
        return heights.sorted(by: >).map { Optional($0) }
    }

    private var canDownload: Bool {
        if links.count > 1 { return true }
        if playlist != nil { return !picked.isEmpty }
        return media != nil && !chosenHeights.isEmpty
    }

    private var downloadTitle: String {
        let count = links.count > 1 ? links.count : (playlist != nil ? picked.count : chosenHeights.count)
        return count > 1 ? "Download \(count)" : "Download"
    }

    private var estimatedTotal: Int64? {
        guard let media, !audioOnly, links.count <= 1 else { return nil }
        let sizes = heights.compactMap { height in media.qualities.first { $0.height == height }?.estimatedBytes }
        guard !sizes.isEmpty, sizes.count == heights.count else { return nil }
        return sizes.reduce(0, +)
    }

    private func converts(_ media: RemoteMedia) -> Bool {
        [.mp4, .mov].contains(format) && heights.contains { $0 > 1080 } && media.site == "YouTube"
    }

    private func prefill() {
        format = state.preferences.settings(for: .video).format
        if !OutputFormat.allCases.contains(format) { format = .mp4 }
        if let clipboard = NSPasteboard.general.string(forType: .string), !LinkDetector.links(in: clipboard).isEmpty {
            text = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Reads the single pasted link: installs the engine the first time, then fetches title and sizes.
    private func read() async {
        guard links.count == 1, let link = links.first else {
            phase = .idle
            return
        }
        if case .ready(let current) = phase, current.link == link { return }
        if case .list(let current) = phase, current.link == link { return }
        phase = .reading
        try? await Task.sleep(for: .milliseconds(250))  // let typing settle
        guard !Task.isCancelled else { return }
        do {
            try await state.downloader.ensureReady()
            let contents = try await state.downloader.engine.read(link)
            guard !Task.isCancelled else { return }
            switch contents {
            case .single(let media):
                heights = Self.defaultHeights(media.qualities)
                phase = .ready(media)
            case .playlist(let list):
                picked = Set(list.entries.map(\.id))
                phase = .list(list)
            }
        } catch {
            if !Task.isCancelled { phase = .failed(error.localizedDescription) }
        }
    }

    /// Full HD when offered (plays everywhere without converting), else the tallest.
    static func defaultHeights(_ qualities: [RemoteMedia.Quality]) -> Set<Int> {
        if let fullHD = qualities.first(where: { $0.height == 1080 }) { return [fullHD.height] }
        return qualities.first.map { [$0.height] } ?? []
    }

    private func download() {
        guard canDownload else { return }
        if links.count > 1 {
            state.queue.addLinks(links, format: format, height: audioOnly ? nil : batchLimit, start: true)
        } else if let playlist {
            let chosen = playlist.entries.filter { picked.contains($0.id) }
            state.queue.addDownloads(chosen, heights: [audioOnly ? nil : batchLimit], format: format)
        } else if let media {
            state.queue.addDownloads(media, heights: chosenHeights, format: format)
        }
        dismiss()
    }
}

/// Thumbnail, title and details of the link.
private struct PreviewCard: View {
    let media: RemoteMedia

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: media.thumbnail) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    KindArtwork(kind: media.kind, size: 44)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                if let duration = media.duration, duration > 0 {
                    Text(MediaInfo.formatDuration(duration))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(media.title)
                    .font(.headline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text([media.site, media.uploader].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The resolutions on offer as chips. Several can be chosen; at least one stays chosen.
private struct QualityPicker: View {
    let qualities: [RemoteMedia.Quality]
    @Binding var selection: Set<Int>

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Resolution").font(.callout.weight(.medium))
                Spacer()
                Text(selection.count > 1 ? "\(selection.count) sizes, saved side by side" : "Choose one or more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(qualities) { quality in
                    QualityChip(quality: quality, isSelected: selection.contains(quality.height)) { toggle(quality.height) }
                }
            }
        }
    }

    private func toggle(_ height: Int) {
        withAnimation(Theme.motion) {
            if selection.contains(height) {
                if selection.count > 1 { selection.remove(height) }
            } else {
                selection.insert(height)
            }
        }
    }
}

private struct QualityChip: View {
    let quality: RemoteMedia.Quality
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if isSelected { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                    Text(quality.label).font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.1 : 0.06)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help([quality.nickname, quality.estimatedBytes.map { "about \($0.fileSizeText)" }].compactMap { $0 }.joined(separator: ", "))
        .accessibilityLabel(quality.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        if let bytes = quality.estimatedBytes { return bytes.fileSizeText }
        return quality.nickname ?? " "
    }
}

/// Several links: a short list and one size limit for all of them.
private struct BatchSummary: View {
    let links: [URL]
    @Binding var limit: Int?
    let audioOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(links.prefix(5), id: \.self) { link in
                    Label(LinkDetector.knownSite(for: link).map { "\($0) · \(link.path())" } ?? link.absoluteString, systemImage: "link")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if links.count > 5 { Text("and \(links.count - 5) more").foregroundStyle(.secondary) }
            }
            .font(.callout)
            if !audioOnly {
                HStack {
                    Text("Resolution")
                    Picker("Resolution", selection: $limit) {
                        Text("Best available").tag(Int?.none)
                        Divider()
                        ForEach([2160, 1440, 1080, 720, 480, 360], id: \.self) { height in
                            Text("Up to " + RemoteMedia.Quality(height: height, estimatedBytes: nil).label).tag(Int?.some(height))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                .font(.callout)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A playlist or channel: its videos with checkboxes, and one resolution limit for all of them.
private struct PlaylistPanel: View {
    let playlist: Playlist
    @Binding var picked: Set<String>
    @Binding var limit: Int?
    let audioOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).font(.headline).lineLimit(1)
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(picked.count == playlist.entries.count ? "Select None" : "Select All") {
                    picked = picked.count == playlist.entries.count ? [] : Set(playlist.entries.map(\.id))
                }
                .buttonStyle(.link)
            }
            List {
                ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                    Toggle(isOn: Binding(get: { picked.contains(entry.id) }, set: { on in
                        if on { picked.insert(entry.id) } else { picked.remove(entry.id) }
                    })) {
                        HStack(spacing: 10) {
                            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 26, alignment: .trailing)
                            AsyncImage(url: entry.thumbnail) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.secondary.opacity(0.15) }
                                .frame(width: 56, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text(entry.title).lineLimit(1)
                            Spacer()
                            if let duration = entry.duration { Text(MediaInfo.formatDuration(duration)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: min(CGFloat(playlist.entries.count) * 40 + 8, 260))
            if !audioOnly {
                HStack {
                    Text("Resolution")
                    Picker("Resolution", selection: $limit) {
                        Text("Best available").tag(Int?.none)
                        Divider()
                        ForEach([2160, 1440, 1080, 720, 480, 360], id: \.self) { height in
                            Text("Up to " + RemoteMedia.Quality(height: height, estimatedBytes: nil).label).tag(Int?.some(height))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                .font(.callout)
            }
        }
    }

    private var summary: String {
        var parts = ["\(picked.count) of \(playlist.entries.count) videos"]
        if let uploader = playlist.uploader { parts.insert(uploader, at: 0) }
        let total = playlist.entries.filter { picked.contains($0.id) }.compactMap(\.duration).reduce(0, +)
        if total > 0 { parts.append(MediaInfo.formatDuration(total)) }
        if playlist.entries.count >= DownloadEngine.playlistLimit { parts.append("first \(DownloadEngine.playlistLimit) shown") }
        return parts.joined(separator: " · ")
    }
}
