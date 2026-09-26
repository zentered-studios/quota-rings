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
        for url in newestLogs() {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            if let limits = CodexParser.latestLimits(inLog: data, now: now) { return limits }
        }
        return nil
    }

    /// Logs live in `sessions/YYYY/MM/DD/`. Walks the newest day folders first and sorts
    /// each day by modification date, so a long session started yesterday still counts.
    private static func newestLogs() -> [URL] {
        let fm = FileManager.default
        func children(_ url: URL) -> [URL] {
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: .skipsHiddenFiles)) ?? []
            return items.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }

        var logs: [URL] = []
        var days = 0
        search: for year in children(sessionsDirectory) {
            for month in children(year) {
                for day in children(month) {
                    logs += children(day).filter { $0.pathExtension == "jsonl" }
                    days += 1
                    // A second day covers a session that started before midnight and still runs.
                    if days >= 2 && logs.count >= maxLogs { break search }
                }
            }
        }
        return Array(logs.sorted { modified($0) > modified($1) }.prefix(maxLogs))
    }
}
