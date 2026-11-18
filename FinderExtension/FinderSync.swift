import AppKit
import ConvetaKit
import FinderSync
import UniformTypeIdentifiers

/// Adds "Convert with Conveta" to Finder's right-click menu for media files.
/// The extension only builds the menu and hands the choice to the app; the app does the work.
/// Finder calls every method here on the main thread.
final class FinderSync: FIFinderSync {
    /// Formats offered for the current selection, indexed by menu item tag.
    private var offered: [OutputFormat] = []

    override init() {
        super.init()
        // Watch only the root. Finder shows a sync extension's icon on every watched folder that
        // appears in the sidebar, so watching volumes (or Desktop, Documents...) would replace their
        // icons with Conveta's. Never add sidebar locations here.
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/"), URL(filePath: "/Volumes")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty
        else { return nil }

        let kinds = Set(urls.compactMap(Self.kind(of:)))
        // Only show the menu when every selected item is something Conveta converts.
        guard kinds.count > 0, urls.allSatisfy({ Self.kind(of: $0) != nil }) else { return nil }
        offered = MediaKind.commonFormats(for: Array(kinds).sorted { $0.rawValue < $1.rawValue })

        let menu = NSMenu(title: "")
        let submenu = NSMenu(title: "Convert with Conveta")
        for (index, format) in offered.enumerated() {
            let item = NSMenuItem(title: format.displayName, action: #selector(convert(_:)), keyEquivalent: "")
            item.tag = index
            item.toolTip = format.summary
            submenu.addItem(item)
        }
        if !offered.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(NSMenuItem(title: "Open in Conveta…", action: #selector(openInApp(_:)), keyEquivalent: ""))

        let root = NSMenuItem(title: "Convert with Conveta", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc private func convert(_ sender: NSMenuItem) {
        guard offered.indices.contains(sender.tag) else { return }
        handOff(format: offered[sender.tag])
    }

    @objc private func openInApp(_ sender: NSMenuItem) {
        handOff(format: nil)
    }

    private func handOff(format: OutputFormat?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        let request = HandoffRequest(paths: urls.map(\.path), format: format)
        AppGroup.handoffs.save(request)
        NSWorkspace.shared.open(HandoffStore.url(for: request))
    }

    static func kind(of url: URL) -> MediaKind? {
        if url.hasDirectoryPath { return nil }
        return MediaKind(url: url)
    }
}
