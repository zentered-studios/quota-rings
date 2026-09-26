import Foundation

/// Reads Codex plan limits from a Codex session log (`~/.codex/sessions/**/rollout-*.jsonl`).
///
/// Codex appends a `token_count` event with the account's `rate_limits` after each model
/// response. The log format is not a documented public API and can change without notice.
enum CodexParser {
    private static let marker = Data(#""rate_limits""#.utf8)

    /// Limits from the newest `rate_limits` event in the log, or nil when it has none.
    /// A window whose reset time has passed shows 0%, because the log only updates when Codex runs.
    static func latestLimits(inLog data: Data, now: Date) -> [UsageLimit]? {
        var end = data.endIndex
        while end > data.startIndex {
            let start = data[data.startIndex..<end].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
            let line = data[start..<end]
            if line.range(of: marker) != nil, let limits = parseEvent(Data(line), now: now) {
                return limits
            }
            guard start > data.startIndex else { break }
            end = start - 1
        }
        return nil
    }

    private static func parseEvent(_ line: Data, now: Date) -> [UsageLimit]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let payload = root["payload"] as? [String: Any],
            payload["type"] as? String == "token_count",
            let rateLimits = payload["rate_limits"] as? [String: Any]
        else { return nil }
        // Other limit ids (seen: "premium") are separate pools, not the plan limit.
        if let id = rateLimits["limit_id"] as? String, id != "codex" { return nil }

        let windows = ["primary", "secondary"]
            .compactMap { rateLimits[$0] as? [String: Any] }
            .compactMap { window(from: $0, now: now) }
        // No window to show: keep looking at older events.
        guard !windows.isEmpty else { return nil }
        return windows.sorted { $0.minutes < $1.minutes }.map(\.limit)
    }

    private static func window(from obj: [String: Any], now: Date) -> (minutes: Int, limit: UsageLimit)? {
        guard let percent = (obj["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = (obj["window_minutes"] as? NSNumber)?.intValue ?? 0
        var resetsAt = (obj["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        var used = percent
        if let reset = resetsAt, reset <= now {
            used = 0
            resetsAt = nil
        }
        let kind: UsageLimit.Kind = minutes > 0 && minutes <= 24 * 60 ? .session : .weekly
        let limit = UsageLimit(kind: kind, label: label(minutes: minutes), percent: used, resetsAt: resetsAt, severity: "normal")
        return (minutes, limit)
    }

    /// "Session" for the 5 hour window, "Week" for 7 days, otherwise the length.
    static func label(minutes: Int) -> String {
        switch minutes {
        case 300: return "Session"
        case 10080: return "Week"
        case let m where m > 0 && m % 1440 == 0: return "\(m / 1440)d"
        case let m where m > 0 && m % 60 == 0: return "\(m / 60)h"
        case let m where m > 0: return "\(m)m"
        default: return "Limit"
        }
    }
}
