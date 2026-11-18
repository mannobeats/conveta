import ConvetaKit
import Foundation
import Observation

/// Where converted files go.
enum Destination: String, Codable, CaseIterable, Identifiable {
    case nextToOriginal
    case downloads
    case folder

    var id: String { rawValue }
}

/// The person's choices, stored in UserDefaults and applied at once.
@Observable
final class Preferences {
    /// The settings a new file of each kind starts with. Edited in the inspector, so the last
    /// choice for videos is remembered for the next video.
    var defaults: [MediaKind: ConversionSettings] { didSet { save(defaults, Key.defaults) } }
    var destination: Destination { didSet { store.set(destination.rawValue, forKey: Key.destination) } }
    /// Security-scoped bookmark of the custom output folder.
    var customFolder: Data? { didSet { store.set(customFolder, forKey: Key.customFolder) } }
    var revealWhenDone: Bool { didSet { store.set(revealWhenDone, forKey: Key.reveal) } }
    var notifyWhenDone: Bool { didSet { store.set(notifyWhenDone, forKey: Key.notify) } }
    var playSoundWhenDone: Bool { didSet { store.set(playSoundWhenDone, forKey: Key.sound) } }
    var startImmediately: Bool { didSet { store.set(startImmediately, forKey: Key.startImmediately) } }
    /// How many files convert at once. Video encoders share the media engine, so more is not always faster.
    var parallelJobs: Int { didSet { store.set(parallelJobs, forKey: Key.parallel) } }
    /// A browser whose sign-ins downloads may use ("safari", "chrome"...), for posts that need an account.
    var cookiesBrowser: String? { didSet { store.set(cookiesBrowser, forKey: Key.cookies) } }

    @ObservationIgnored private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        if let data = store.data(forKey: Key.defaults),
           let saved = try? JSONDecoder().decode([MediaKind: ConversionSettings].self, from: data) {
            defaults = saved
        } else {
            defaults = [:]
        }
        destination = store.string(forKey: Key.destination).flatMap(Destination.init(rawValue:)) ?? .nextToOriginal
        customFolder = store.data(forKey: Key.customFolder)
        revealWhenDone = store.object(forKey: Key.reveal) as? Bool ?? false
        notifyWhenDone = store.object(forKey: Key.notify) as? Bool ?? true
        playSoundWhenDone = store.object(forKey: Key.sound) as? Bool ?? true
        startImmediately = store.object(forKey: Key.startImmediately) as? Bool ?? false
        parallelJobs = store.object(forKey: Key.parallel) as? Int ?? Self.recommendedParallelJobs
        cookiesBrowser = store.string(forKey: Key.cookies)
    }

    static var recommendedParallelJobs: Int {
        min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 3))
    }

    func settings(for kind: MediaKind) -> ConversionSettings {
        if let saved = defaults[kind], kind.outputFormats.contains(saved.format) { return saved }
        return ConversionSettings(format: kind.defaultFormat)
    }

    func remember(_ settings: ConversionSettings, for kind: MediaKind) {
        guard kind.outputFormats.contains(settings.format), defaults[kind] != settings else { return }
        defaults[kind] = settings
    }

    func resetDefaults() {
        defaults = [:]
    }

    private func save<Value: Encodable>(_ value: Value, _ key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private enum Key {
        static let defaults = "conversionDefaults"
        static let destination = "destination"
        static let customFolder = "customFolderBookmark"
        static let reveal = "revealWhenDone"
        static let notify = "notifyWhenDone"
        static let sound = "playSoundWhenDone"
        static let startImmediately = "startImmediately"
        static let parallel = "parallelJobs"
        static let cookies = "cookiesBrowser"
    }
}
