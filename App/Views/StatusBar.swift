import ConvetaKit
import SwiftUI

/// The strip under the list: where files are saved, and how the batch is going.
struct StatusBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let queue = state.queue
        HStack(spacing: 12) {
            DestinationMenu()
            Spacer(minLength: 12)
            if queue.isRunning {
                ProgressView(value: queue.batchProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 140)
                    .accessibilityLabel("Overall progress")
                Text(remainingText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } else if let summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(Theme.motion, value: queue.isRunning)
    }

    private var remainingText: String {
        let left = state.queue.jobs.filter(\.state.isActive).count
        return left == 1 ? "1 file left" : "\(left) files left"
    }

    /// After a batch: how much space the converted files saved.
    private var summary: String? {
        let done = state.queue.finishedJobs
        guard !done.isEmpty else { return nil }
        let before = done.reduce(Int64(0)) { $0 + ($1.info?.fileSize ?? 0) }
        let after = done.reduce(Int64(0)) { $0 + ($1.outputSize ?? 0) }
        let count = done.count == 1 ? "1 file done" : "\(done.count) files done"
        guard before > after, before > 0 else { return count }
        return "\(count) · \((before - after).fileSizeText) saved"
    }
}

/// "Save to: Next to Originals ▾", with Downloads and a chosen folder.
struct DestinationMenu: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let preferences = state.preferences
        Menu {
            Picker("Save To", selection: Binding(get: { preferences.destination }, set: { preferences.destination = $0 })) {
                Label("Next to Originals", systemImage: "folder").tag(Destination.nextToOriginal)
                Label("Downloads", systemImage: "arrow.down.circle").tag(Destination.downloads)
                if let name = customFolderName {
                    Label(name, systemImage: "folder.badge.gearshape").tag(Destination.folder)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Choose Folder…") { chooseFolder() }
            Divider()
            Text("Downloads from links go to Downloads when saving next to originals.")
        } label: {
            Label {
                Text("\(Text("Save to:").foregroundStyle(.secondary)) \(title)")
            } icon: {
                Image(systemName: "folder")
            }
            .font(.callout)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Where converted files are saved")
    }

    private var title: String {
        switch state.preferences.destination {
        case .nextToOriginal: "Next to Originals"
        case .downloads: "Downloads"
        case .folder: customFolderName ?? "Chosen Folder"
        }
    }

    private var customFolderName: String? {
        var stale = false
        return state.preferences.customFolder
            .flatMap { try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) }?
            .lastPathComponent
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose where Conveta saves converted files."
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        state.access.grant(url)
        state.preferences.customFolder = bookmark
        state.preferences.destination = .folder
    }
}
