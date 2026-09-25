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

/// What the host app writes to disk and the widget reads.
struct UsageSnapshot: Codable {
    var limits: [UsageLimit]
    var fetchedAt: Date
    /// Set when the last fetch failed. `limits` then holds the previous good values.
    var error: String?

    static let placeholder = UsageSnapshot(
        limits: [
            UsageLimit(kind: .session, label: "Session", percent: 12, resetsAt: Date().addingTimeInterval(3 * 3600), severity: "normal"),
            UsageLimit(kind: .weekly, label: "Week", percent: 64, resetsAt: Date().addingTimeInterval(4 * 86400), severity: "warning"),
            UsageLimit(kind: .model, label: "Fable", percent: 29, resetsAt: Date().addingTimeInterval(4 * 86400), severity: "normal"),
        ],
        fetchedAt: Date(),
        error: nil
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
        realHome.appendingPathComponent("Library/Application Support/ClaudeUsageWidget", isDirectory: true)
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
