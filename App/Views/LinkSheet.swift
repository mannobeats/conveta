import AppKit
import ConvetaKit
import SwiftUI

/// "Download from a Link": paste one or more links from YouTube, Instagram, TikTok and other sites.
/// Opens with a link already filled in when one is on the clipboard.
struct LinkSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var format: OutputFormat = .mp4

    private var links: [URL] { LinkDetector.links(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                KindArtwork(kind: .video, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download from a Link").font(.headline)
                    Text("YouTube, Instagram, TikTok, X, Vimeo and more than a thousand other sites.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Paste a link, or several, one per line", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit(add)

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

            if !text.isEmpty, links.isEmpty {
                Label("That doesn’t look like a web link.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Text("Download only videos you own or have permission to use, and respect each site’s terms.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(links.count > 1 ? "Download \(links.count)" : "Download", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(links.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            if let clipboard = NSPasteboard.general.string(forType: .string), !LinkDetector.links(in: clipboard).isEmpty {
                text = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            format = state.preferences.settings(for: .video).format
        }
    }

    private func add() {
        guard !links.isEmpty else { return }
        state.queue.addLinks(links, format: format, start: true)
        dismiss()
    }
}
