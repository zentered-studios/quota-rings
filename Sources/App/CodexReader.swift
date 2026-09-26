import Foundation

/// Finds the newest Codex session log with plan limits. Reads files only: no network, no token.
enum CodexReader {
    static var sessionsDirectory: URL {
        SnapshotStore.realHome.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// Logs to open before giving up. A new session has no `rate_limits` until its first response.
    private static let maxLogs = 5

    /// Codex limits, or nil when Codex is not installed or has never logged limits.
    static func read(now: Date = Date()) -> [UsageLimit]? {
        for url in CodexParser.newestLogs(in: sessionsDirectory, limit: maxLogs) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            if let limits = CodexParser.latestLimits(inLog: data, now: now) { return limits }
        }
        return nil
    }
}
