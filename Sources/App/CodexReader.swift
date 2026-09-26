import Foundation

/// Reads Codex plan limits from its session logs. Reads files only: no network, no token.
enum CodexReader {
    static var sessionsDirectory: URL {
        SnapshotStore.realHome.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// Logs to open before giving up. A new session has no `rate_limits` until its first response.
    private static let maxLogs = 5

    /// Codex limits, or nil when Codex is not installed or has never logged limits.
    static func read(now: Date = Date()) -> [UsageLimit]? {
        CodexParser.latestLimits(inSessions: sessionsDirectory, logs: maxLogs, now: now)
    }
}
