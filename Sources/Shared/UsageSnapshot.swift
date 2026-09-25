import Foundation

/// One plan limit as shown in the widget: "Session", "Week", or a model-scoped weekly limit such as "Fable".
struct UsageLimit: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case session, weekly, model }

    var kind: Kind
    var label: String
    var percent: Double
    var resetsAt: Date?
    /// "normal", "warning" or "critical" as reported by the API.
    var severity: String

    var id: String { "\(kind.rawValue)-\(label)" }
}

/// Why the last fetch did not produce fresh numbers.
enum UsageStatus: String, Codable {
    /// No Claude Code login in the Keychain.
    case notSignedIn
    /// The stored token expired or the API rejected it. Running `claude` refreshes it.
    case expired
    /// Signed in, but the account has no plan limits (not on Pro or Max).
    case noPlan
    case offline
    case failed

    var title: String {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .expired: return "Sign-in expired"
        case .noPlan: return "No plan limits"
        case .offline: return "Offline"
        case .failed: return "Can't load usage"
        }
    }

    var detail: String {
        switch self {
        case .notSignedIn: return "Sign in to Claude Code in Terminal, then click here."
        case .expired: return "Run claude in Terminal to reconnect."
        case .noPlan: return "Usage limits need a Pro or Max plan."
        case .offline: return "Showing the last known usage."
        case .failed: return "Retrying in 5 minutes."
        }
    }

    var symbol: String {
        switch self {
        case .notSignedIn: return "person.crop.circle.badge.questionmark"
        case .expired: return "clock.badge.exclamationmark"
        case .noPlan: return "gauge.with.dots.needle.0percent"
        case .offline: return "wifi.slash"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Old numbers belong to a different account state and would mislead.
    var clearsLimits: Bool { self == .notSignedIn || self == .noPlan }
}

/// What the host app writes to disk and the widget reads.
struct UsageSnapshot: Codable {
    var limits: [UsageLimit]
    var fetchedAt: Date
    /// Set when the last fetch failed. `limits` may then hold the previous good values.
    var status: UsageStatus?
    /// Technical detail for the last failure, shown in the menu.
    var error: String?

    static let placeholder = UsageSnapshot(
        limits: [
            UsageLimit(kind: .session, label: "Session", percent: 12, resetsAt: Date().addingTimeInterval(3 * 3600), severity: "normal"),
            UsageLimit(kind: .weekly, label: "Week", percent: 64, resetsAt: Date().addingTimeInterval(4 * 86400), severity: "warning"),
            UsageLimit(kind: .model, label: "Fable", percent: 29, resetsAt: Date().addingTimeInterval(4 * 86400), severity: "normal"),
        ],
        fetchedAt: Date()
    )
}

enum SnapshotStore {
    /// The real home directory. In the sandboxed widget `NSHomeDirectory()` points into its container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Must match the widget's `home-relative-path.read-only` entitlement.
    static var directory: URL {
        realHome.appendingPathComponent("Library/Application Support/QuotaRings", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("usage.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
