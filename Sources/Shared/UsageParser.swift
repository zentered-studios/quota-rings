import Foundation

/// Parses the response of `GET https://api.anthropic.com/api/oauth/usage`.
///
/// This endpoint is what Claude Code's `/usage` reads. It is not a documented public API
/// and its shape can change without notice.
enum UsageParser {
    enum ParseError: Error, LocalizedError {
        case noLimits
        var errorDescription: String? { "Usage response contained no limits" }
    }

    static func parse(_ data: Data) throws -> [UsageLimit] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let limits = root["limits"] as? [[String: Any]], !limits.isEmpty {
            let parsed = limits.compactMap(parseLimit)
            if !parsed.isEmpty { return sorted(parsed) }
        }

        // Older response shape: top-level `five_hour` / `seven_day` windows.
        var fallback: [UsageLimit] = []
        if let w = root["five_hour"] as? [String: Any], let l = window(w, kind: .session, label: "Session") {
            fallback.append(l)
        }
        if let w = root["seven_day"] as? [String: Any], let l = window(w, kind: .weekly, label: "Week") {
            fallback.append(l)
        }
        guard !fallback.isEmpty else { throw ParseError.noLimits }
        return fallback
    }

    private static func parseLimit(_ obj: [String: Any]) -> UsageLimit? {
        guard let kindRaw = obj["kind"] as? String, let percent = number(obj["percent"]) else { return nil }
        let resets = date(obj["resets_at"])
        let severity = obj["severity"] as? String ?? "normal"

        switch kindRaw {
        case "session":
            return UsageLimit(kind: .session, label: "Session", percent: percent, resetsAt: resets, severity: severity)
        case "weekly_all":
            return UsageLimit(kind: .weekly, label: "Week", percent: percent, resetsAt: resets, severity: severity)
        case "weekly_scoped":
            let scope = obj["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let surface = scope?["surface"] as? [String: Any]
            let name = model?["display_name"] as? String ?? surface?["display_name"] as? String ?? "Scoped"
            return UsageLimit(kind: .model, label: name, percent: percent, resetsAt: resets, severity: severity)
        default:
            return nil
        }
    }

    private static func window(_ w: [String: Any], kind: UsageLimit.Kind, label: String) -> UsageLimit? {
        guard let percent = number(w["utilization"]) else { return nil }
        return UsageLimit(kind: kind, label: label, percent: percent, resetsAt: date(w["resets_at"]), severity: "normal")
    }

    private static func sorted(_ limits: [UsageLimit]) -> [UsageLimit] {
        let order: [UsageLimit.Kind: Int] = [.session: 0, .weekly: 1, .model: 2]
        return limits.enumerated()
            .sorted { (order[$0.element.kind]!, $0.offset) < (order[$1.element.kind]!, $1.offset) }
            .map(\.element)
    }

    private static func number(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        // The API sends microseconds (6 digits). ISO8601DateFormatter only accepts up to 3.
        let trimmed = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return isoFractional.date(from: trimmed) ?? iso.date(from: trimmed)
    }
}
