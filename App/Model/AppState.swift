import AppKit
import ConvetaKit
import Foundation
import Observation

/// The app's single source of truth. Every entry point (window, menus, Finder, Services,
/// URLs and Shortcuts) goes through it.
@Observable
final class AppState {
    static let shared = AppState()

    let preferences: Preferences
    let access: FolderAccess
    let queue: ConversionQueue
    var showInspector = true
    var isImporterPresented = false

    @ObservationIgnored private let completion = CompletionFeedback()

    init(store: UserDefaults = .standard) {
        preferences = Preferences(store: store)
        access = FolderAccess(store: store)
        queue = ConversionQueue(preferences: preferences, access: access)
        queue.onBatchFinished = { [weak self] jobs in
            guard let self else { return }
            completion.batchFinished(jobs, preferences: preferences)
        }
    }

    // MARK: Entry points

    /// Files opened from Finder (Open With, Dock icon, double-click) or dropped on the window.
    func open(_ urls: [URL], format: OutputFormat? = nil, start: Bool = false) {
        queue.add(urls, format: format, start: start)
        NSApp.activate()
    }

    /// `conveta://handoff?id=…` from the Finder extension, or `conveta://action/<name>`.
    func handle(_ url: URL) {
        if let id = HandoffStore.requestID(in: url) {
            guard let request = AppGroup.handoffs.take(id) else { return }
            receive(request)
            return
        }
        guard url.scheme == HandoffStore.urlScheme, url.host() == "action" else { return }
        switch url.lastPathComponent {
        case "convert": queue.convertSelectionOrAll()
        case "stop": queue.cancelAll()
        case "add": isImporterPresented = true
        case "clear": queue.clearFinished()
        default: break
        }
        NSApp.activate()
    }

    /// Files handed over by Finder arrive as paths only, so the sandbox may need the folder granted first.
    func receive(_ request: HandoffRequest) {
        let urls = request.urls
        let unreadable = urls.filter { !access.canRead($0) }.map { $0.deletingLastPathComponent() }
        if let folder = FolderAccess.commonAncestor(of: unreadable) {
            NSApp.activate()
            access.requestAccess(to: folder, reason: "To convert files from Finder, Conveta needs permission to open “\(folder.lastPathComponent)”. Choosing your home folder covers every folder inside it, so you’re only asked once.")
        }
        open(urls.filter(access.canRead), format: request.format, start: request.format != nil)
    }
}
