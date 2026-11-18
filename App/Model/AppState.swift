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
    let downloader: Downloader
    let presets = PresetLibrary(store: PresetStore(suiteName: AppGroup.identifier))
    var showInspector = true
    var isImporterPresented = false
    var isLinkSheetPresented = false

    @ObservationIgnored private let completion = CompletionFeedback()

    init(store: UserDefaults = .standard) {
        preferences = Preferences(store: store)
        access = FolderAccess(store: store)
        downloader = Downloader(preferences: preferences, store: store,
                                ffmpegFolder: FFmpegTools.bundled()?.ffmpeg.deletingLastPathComponent())
        queue = ConversionQueue(preferences: preferences, access: access, downloader: downloader)
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

    /// `conveta://handoff?id=…` from the Finder extension, `conveta://download?url=…&format=mp3`,
    /// or `conveta://action/<name>`.
    func handle(_ url: URL) {
        if let id = HandoffStore.requestID(in: url) {
            guard let request = AppGroup.handoffs.take(id) else { return }
            receive(request)
            return
        }
        if url.scheme == HandoffStore.urlScheme, url.host() == "download" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let links = items.filter { $0.name == "url" }.compactMap { $0.value.flatMap(URL.init(string:)) }.filter(LinkDetector.isWebLink)
            let format = items.first { $0.name == "format" }?.value.flatMap(OutputFormat.init(rawValue:))
            queue.addLinks(links, format: format, start: format != nil)
            NSApp.activate()
            return
        }
        guard url.scheme == HandoffStore.urlScheme, url.host() == "action" else { return }
        switch url.lastPathComponent {
        case "convert": queue.convertSelectionOrAll()
        case "stop": queue.cancelAll()
        case "add": isImporterPresented = true
        case "link": isLinkSheetPresented = true
        case "clear": queue.clearFinished()
        default: break
        }
        NSApp.activate()
    }

    /// Adds the links found in pasted text. Returns whether there were any.
    @discardableResult
    func pasteLinks(_ text: String) -> Bool {
        let links = LinkDetector.links(in: text)
        guard !links.isEmpty else { return false }
        queue.addLinks(links)
        return true
    }

    /// Files handed over by Finder arrive as paths only; the folder may need to be allowed first.
    func receive(_ request: HandoffRequest) {
        let urls = request.urls
        let unreadable = urls.filter { !access.canRead($0) }.map { $0.deletingLastPathComponent() }
        if let folder = FolderAccess.commonAncestor(of: unreadable) {
            NSApp.activate()
            access.requestAccess(to: folder, reason: "To convert files from Finder, Conveta needs permission to open “\(folder.lastPathComponent)”. Choosing your home folder covers every folder inside it, so you’re only asked once.")
        }
        let readable = urls.filter(access.canRead)
        if let id = request.presetID, let preset = presets.preset(id: id) {
            queue.add(readable, preset: preset)
            NSApp.activate()
        } else {
            open(readable, format: request.format, start: request.format != nil)
        }
    }
}
