import AppKit
import Foundation

/// The folders the sandbox lets Conveta read and write, kept across launches as security-scoped bookmarks.
///
/// Dropped and opened files can be read but not written next to. To save beside the originals,
/// or to read files handed over from Finder, Conveta asks once for the folder; a parent folder
/// (such as the home folder) covers everything inside it.
@Observable
final class FolderAccess {
    private(set) var grantedFolders: [URL] = []

    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private var bookmarks: [Data]
    private static let key = "grantedFolderBookmarks"

    init(store: UserDefaults = .standard) {
        self.store = store
        bookmarks = store.array(forKey: Self.key) as? [Data] ?? []
        resolveAll()
    }

    /// Whether Conveta can create files in `folder` right now.
    func canWrite(to folder: URL) -> Bool {
        let probe = folder.appending(path: ".conveta-access-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: probe.path, contents: nil) else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    func canRead(_ file: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: file.path)
    }

    /// Asks the person to grant `folder` (or any folder above it). Returns whether access now works.
    @discardableResult
    func requestAccess(to folder: URL, reason: String) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.title = "Allow Access"
        panel.message = reason
        panel.prompt = "Allow Access"
        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        grant(chosen)
        return canWrite(to: folder) || canRead(folder)
    }

    /// Stores a bookmark for a folder the person picked in an open panel.
    func grant(_ folder: URL) {
        guard let data = try? folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        _ = folder.startAccessingSecurityScopedResource()
        if !grantedFolders.contains(folder.standardizedFileURL) {
            bookmarks.append(data)
            grantedFolders.append(folder.standardizedFileURL)
            store.set(bookmarks, forKey: Self.key)
        }
    }

    func revoke(_ folder: URL) {
        guard let index = grantedFolders.firstIndex(of: folder.standardizedFileURL) else { return }
        folder.stopAccessingSecurityScopedResource()
        grantedFolders.remove(at: index)
        bookmarks.remove(at: index)
        store.set(bookmarks, forKey: Self.key)
    }

    /// The deepest folder containing all of `folders`, or `nil` when there are none.
    static func commonAncestor(of folders: [URL]) -> URL? {
        let paths = folders.map { $0.standardizedFileURL.pathComponents }
        guard var shared = paths.first else { return nil }
        for components in paths.dropFirst() {
            shared = Array(zip(shared, components).prefix { $0 == $1 }.map(\.0))
        }
        return URL(filePath: shared.isEmpty ? "/" : NSString.path(withComponents: shared), directoryHint: .isDirectory)
    }

    /// Opens every saved bookmark; drops the ones whose folder is gone.
    private func resolveAll() {
        var kept: [Data] = []
        for data in bookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            let fresh = stale ? (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? data : data
            kept.append(fresh)
            grantedFolders.append(url.standardizedFileURL)
        }
        bookmarks = kept
        store.set(bookmarks, forKey: Self.key)
    }
}
