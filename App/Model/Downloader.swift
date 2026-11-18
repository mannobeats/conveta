import ConvetaKit
import Foundation
import Observation

/// Owns the download engine (yt-dlp): installs it the first time a link is added, keeps it current
/// (sites change often and an old engine stops working), and hands out a configured engine.
@Observable
final class Downloader {
    enum Status: Equatable {
        case notInstalled
        case installing
        case ready(version: String)
        case failed(String)
    }

    private(set) var status: Status = .notInstalled
    private(set) var lastChecked: Date?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let ffmpegFolder: URL?
    @ObservationIgnored private var installTask: Task<Void, Error>?
    /// How long an engine is trusted before Conveta looks for a newer one.
    static let refreshInterval: TimeInterval = 3 * 24 * 3600

    init(preferences: Preferences, store: UserDefaults = .standard, ffmpegFolder: URL?) {
        self.preferences = preferences
        self.store = store
        self.ffmpegFolder = ffmpegFolder
        lastChecked = store.object(forKey: "downloaderLastChecked") as? Date
        Task { await refreshStatus() }
    }

    static var executable: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Conveta/Engines/yt-dlp")
    }

    var engine: DownloadEngine {
        DownloadEngine(executable: Self.executable, ffmpegFolder: ffmpegFolder, cookiesBrowser: preferences.cookiesBrowser)
    }

    var version: String? {
        if case .ready(let version) = status { version } else { nil }
    }

    /// Installs the engine if needed; waits for an install already running. Throws if it can't.
    func ensureReady() async throws {
        if engine.isInstalled {
            if version == nil { await refreshStatus() }
            Task { await updateIfStale() }
            return
        }
        try await install()
    }

    /// Downloads the newest engine (or waits for the download already under way).
    func install() async throws {
        if let installTask { return try await installTask.value }
        status = .installing
        let engine = engine
        let task = Task { try await engine.install() }
        installTask = task
        defer { installTask = nil }
        do {
            try await task.value
            markChecked()
            await refreshStatus()
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Replaces the engine when GitHub has a newer release. Quiet on failure: the old one keeps working.
    func updateIfStale(force: Bool = false) async {
        guard engine.isInstalled, installTask == nil else { return }
        if !force, let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.refreshInterval { return }
        guard let latest = try? await DownloadEngine.latestVersion() else { return }
        markChecked()
        if latest != version { try? await install() }
    }

    private func refreshStatus() async {
        if let version = await engine.version() {
            status = .ready(version: version)
        } else if status != .installing {
            status = .notInstalled
        }
    }

    private func markChecked() {
        lastChecked = .now
        store.set(lastChecked, forKey: "downloaderLastChecked")
    }
}
