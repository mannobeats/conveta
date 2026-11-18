import ConvetaKit
import SwiftUI
import UniformTypeIdentifiers

/// The one window: the queue, a status bar beneath it, and the inspector on the right.
struct MainWindow: View {
    @Environment(AppState.self) private var state
    @State private var isTargeted = false

    var body: some View {
        @Bindable var state = state
        let queue = state.queue

        Group {
            if queue.jobs.isEmpty {
                EmptyDropView(isTargeted: isTargeted) { state.isImporterPresented = true }
            } else {
                QueueList()
                    .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .animation(Theme.motion, value: queue.jobs.isEmpty)
        .dropDestination(for: URL.self) { urls, _ in
            state.open(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted, !queue.jobs.isEmpty { DropHighlight() }
        }
        .navigationTitle("Conveta")
        .navigationSubtitle(subtitle)
        .toolbar { MainToolbar() }
        .inspector(isPresented: $state.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 300, max: 380)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            state.showInspector.toggle()
                        } label: {
                            Label(state.showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Show or hide conversion settings (Control-Command-I)")
                    }
                }
        }
        .fileImporter(isPresented: $state.isImporterPresented,
                      allowedContentTypes: [.movie, .audio, .image, .pdf, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                // Picked files come security-scoped; keep access for as long as the app runs.
                for url in urls { _ = url.startAccessingSecurityScopedResource() }
                state.open(urls)
            }
        }
    }

    private var subtitle: String {
        let jobs = state.queue.jobs
        guard !jobs.isEmpty else { return "" }
        let done = jobs.filter(\.state.isFinished).count
        let count = jobs.count == 1 ? "1 file" : "\(jobs.count) files"
        return done > 0 ? "\(count), \(done) converted" : count
    }
}

/// A tinted outline over the list while files are dragged in.
private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(6)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

struct MainToolbar: ToolbarContent {
    @Environment(AppState.self) private var state

    var body: some ToolbarContent {
        let queue = state.queue
        ToolbarItem(placement: .primaryAction) {
            Button("Add Files", systemImage: "plus") { state.isImporterPresented = true }
                .help("Add files to convert (Command-O)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Clear Finished", systemImage: "checkmark.circle.badge.xmark") { queue.clearFinished() }
                .help("Remove converted files from the list (Option-Command-K)")
                .disabled(!queue.jobs.contains { $0.state.isFinished || $0.state == .cancelled || $0.state.isUnsupported })
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            if queue.isRunning {
                Button("Stop", systemImage: "stop.fill") { queue.cancelAll() }
                    .help("Stop converting (Command-Period)")
            } else {
                Button {
                    queue.convertSelectionOrAll()
                } label: {
                    Label(convertTitle, systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .disabled(!queue.canConvert)
                .help("Convert (Command-Return)")
            }
        }
    }

    private var convertTitle: String {
        let queue = state.queue
        let selected = queue.selectedJobs.filter(\.state.isStartable).count
        let count = selected > 0 ? selected : queue.startableJobs.count
        return count > 1 ? "Convert \(count)" : "Convert"
    }
}
