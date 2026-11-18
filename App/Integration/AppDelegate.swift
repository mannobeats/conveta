import AppKit
import ConvetaKit
import Observation

/// Receives what SwiftUI scenes don't: files and URLs opened from outside, the Services menu,
/// and the Dock tile.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState.shared
    private let dockProgress = DockProgress()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.isRequested {
            SelfTest.run()
            return
        }
        NSApp.servicesProvider = ServiceProvider(state: state)
        NSUpdateDynamicServices()
        dockProgress.observe(state.queue)
        MenuState.shared.track(state.queue)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { state.open(files) }
        for url in urls where !url.isFileURL { state.handle(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.queue.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop converting and quit?"
        alert.informativeText = "Files that are still converting will be cancelled. Files already converted are kept."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Converting")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        state.queue.cancelAll()
        return .terminateNow
    }
}

/// The "Convert with Conveta" item in Finder's Services and Quick Actions menu.
final class ServiceProvider: NSObject {
    private let state: AppState

    init(state: AppState) { self.state = state }

    /// "Add to Conveta" has no user data; "Convert to MP3 with Conveta" and friends carry the format.
    /// Services work on every disk, unlike the Finder Sync menu, which only covers the startup disk.
    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were selected."
            return
        }
        let format = userData.flatMap(OutputFormat.init(rawValue:))
        state.receive(HandoffRequest(paths: urls.map(\.path), format: format))
    }
}

/// Shows the batch's progress as a bar on the Dock icon.
final class DockProgress {
    private let bar = NSProgressIndicator()
    private var queue: ConversionQueue?

    func observe(_ queue: ConversionQueue) {
        self.queue = queue
        update()
    }

    private func update() {
        guard let queue else { return }
        withObservationTracking {
            render(running: queue.isRunning, progress: queue.batchProgress)
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
    }

    private func render(running: Bool, progress: Double) {
        let tile = NSApp.dockTile
        guard running else {
            tile.contentView = nil
            tile.display()
            return
        }
        if tile.contentView == nil {
            let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.image = NSApp.applicationIconImage
            bar.style = .bar
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 1
            bar.frame = NSRect(x: tile.size.width * 0.1, y: tile.size.height * 0.06, width: tile.size.width * 0.8, height: 14)
            view.addSubview(bar)
            tile.contentView = view
        }
        bar.doubleValue = progress
        tile.display()
    }
}
