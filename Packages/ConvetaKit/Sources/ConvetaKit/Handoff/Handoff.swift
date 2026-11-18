import Foundation

/// A request from the Finder extension (or Services, or a script) to convert files.
/// The extension stores it in the shared app group and opens `conveta://handoff?id=…`;
/// the app takes it out exactly once.
public struct HandoffRequest: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var paths: [String]
    /// `nil` opens the files in Conveta without starting a conversion.
    public var format: OutputFormat?
    /// A preset to convert with, instead of a bare format.
    public var presetID: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), paths: [String], format: OutputFormat?, presetID: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.paths = paths
        self.format = format
        self.presetID = presetID
        self.createdAt = createdAt
    }

    public var urls: [URL] { paths.map { URL(filePath: $0) } }
}

/// Shared storage for hand-offs. Requests older than `lifetime` are ignored and swept.
public struct HandoffStore: Sendable {
    public static let urlScheme = "conveta"
    static let key = "pendingHandoffs"
    public static let lifetime: TimeInterval = 120

    private let suiteName: String?

    /// `suiteName` is the app group; `nil` uses standard defaults (tests).
    public init(suiteName: String?) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func save(_ request: HandoffRequest, now: Date = .now) {
        var pending = load(now: now)
        pending.append(request)
        store(pending)
    }

    /// Removes and returns the request with `id`, if it exists and is fresh.
    public func take(_ id: UUID, now: Date = .now) -> HandoffRequest? {
        var pending = load(now: now)
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        let request = pending.remove(at: index)
        store(pending)
        return request
    }

    /// The URL that asks the app to pick up a request.
    public static func url(for request: HandoffRequest) -> URL {
        URL(string: "\(urlScheme)://handoff?id=\(request.id.uuidString)")!
    }

    /// The request id in a hand-off URL, if it is one.
    public static func requestID(in url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host() == "handoff",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
        else { return nil }
        return UUID(uuidString: value)
    }

    private func load(now: Date) -> [HandoffRequest] {
        guard let data = defaults.data(forKey: Self.key),
              let all = try? JSONDecoder().decode([HandoffRequest].self, from: data) else { return [] }
        return all.filter { now.timeIntervalSince($0.createdAt) < Self.lifetime }
    }

    private func store(_ requests: [HandoffRequest]) {
        defaults.set(try? JSONEncoder().encode(requests), forKey: Self.key)
    }
}
