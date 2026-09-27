import Foundation

// Run with scripts/test.sh. Plain asserts keep this runnable without an XCTest bundle.

var failures = 0
func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

// Trimmed from a real /api/oauth/usage response on 2026-09-25.
let current = #"""
{
  "five_hour": {"utilization": 12.0, "resets_at": "2026-09-26T00:19:59.723382+00:00"},
  "seven_day": {"utilization": 95.0, "resets_at": "2026-09-30T16:59:59.723404+00:00"},
  "limits": [
    {"kind": "session", "group": "session", "percent": 12, "severity": "normal",
     "resets_at": "2026-09-26T00:19:59.723382+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_all", "group": "weekly", "percent": 95, "severity": "critical",
     "resets_at": "2026-09-30T16:59:59.723404+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 29, "severity": "normal",
     "resets_at": "2026-09-30T16:59:59.723590+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
  ]
}
"""#

do {
    let limits = try UsageParser.parse(Data(current.utf8))
    expect(limits.map(\.label) == ["Session", "Week", "Fable"], "labels: \(limits.map(\.label))")
    expect(limits.map(\.percent) == [12, 95, 29], "percents: \(limits.map(\.percent))")
    expect(limits[1].severity == "critical", "weekly severity")
    expect(limits[2].kind == .model, "fable kind")
    let expectedReset = ISO8601DateFormatter().date(from: "2026-09-26T00:19:59Z")!
    let reset = limits[0].resetsAt
    expect(reset != nil && abs(reset!.timeIntervalSince(expectedReset) - 0.723) < 0.01,
           "session reset parsed with microseconds: \(String(describing: reset))")
} catch {
    expect(false, "current shape threw \(error)")
}

// Scoped limits listed before global ones still sort session, week, model.
let unordered = #"""
{"limits": [
  {"kind": "weekly_scoped", "percent": 5, "scope": {"model": {"display_name": "Fable"}}},
  {"kind": "weekly_all", "percent": 50},
  {"kind": "unknown_future_kind", "percent": 1},
  {"kind": "session", "percent": 7}
]}
"""#
do {
    let limits = try UsageParser.parse(Data(unordered.utf8))
    expect(limits.map(\.label) == ["Session", "Week", "Fable"], "sorted labels: \(limits.map(\.label))")
    expect(limits.allSatisfy { $0.resetsAt == nil }, "missing resets_at is nil")
} catch {
    expect(false, "unordered threw \(error)")
}

// Older shape without `limits` falls back to five_hour / seven_day.
let legacy = #"{"five_hour": {"utilization": 40.5, "resets_at": "2026-09-26T00:19:59+00:00"}, "seven_day": {"utilization": 10}}"#
do {
    let limits = try UsageParser.parse(Data(legacy.utf8))
    expect(limits.map(\.label) == ["Session", "Week"], "legacy labels")
    expect(limits[0].percent == 40.5, "legacy percent")
    expect(limits[0].resetsAt != nil, "legacy reset without fraction")
} catch {
    expect(false, "legacy threw \(error)")
}

// No usable data is an error, not an empty widget.
do {
    _ = try UsageParser.parse(Data(#"{"limits": []}"#.utf8))
    expect(false, "empty response should throw")
} catch {}

// Snapshot round-trips through the on-disk format.
do {
    let data = try SnapshotStore.encoder.encode(UsageSnapshot.placeholder)
    let back = try SnapshotStore.decoder.decode(UsageSnapshot.self, from: data)
    expect(back.limits.map(\.label) == UsageSnapshot.placeholder.limits.map(\.label), "snapshot round-trip")
} catch {
    expect(false, "snapshot round-trip threw \(error)")
}

// Credential sessions refuse redirects: the delegate answers nil for any redirect target.
do {
    let original = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let task = URLSession(configuration: .ephemeral).dataTask(with: original) // never resumed, no network
    let redirect = HTTPURLResponse(url: original, statusCode: 302, httpVersion: "HTTP/1.1",
                                   headerFields: ["Location": "https://example.com/"])!
    var request = URLRequest(url: URL(string: "https://example.com/")!)
    request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
    var followed: URLRequest?? = .none
    NoRedirectDelegate().urlSession(URLSession.credentialSession(), task: task, willPerformHTTPRedirection: redirect,
                                    newRequest: request) { followed = .some($0) }
    expect(followed != nil, "delegate answered")
    expect(followed! == nil, "redirect refused, token not forwarded")
}


// Codex: lines trimmed from a real ~/.codex/sessions log on 2026-09-26.
let codexNow = Date(timeIntervalSince1970: 1790442000) // 2026-09-26T17:00:00Z
func codexEvent(_ rateLimits: String) -> String {
    #"{"timestamp":"2026-09-26T17:03:20.449Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":"#
        + rateLimits + "}}"
}
let prolite = #"{"limit_id":"codex","limit_name":null,"primary":{"used_percent":69.0,"window_minutes":10080,"resets_at":1790610676},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"prolite"}"#
let older = #"{"limit_id":"codex","primary":{"used_percent":50.0,"window_minutes":10080,"resets_at":1790610676},"secondary":null}"#
let codexLog = [
    #"{"timestamp":"2026-09-26T16:00:00.000Z","type":"session_meta","payload":{"id":"x"}}"#,
    codexEvent(older),
    codexEvent(prolite),
    #"{"timestamp":"2026-09-26T17:03:21.000Z","type":"response_item","payload":{"type":"message"}}"#,
    "",
].joined(separator: "\n")

if let limits = CodexParser.latestLimits(inLog: Data(codexLog.utf8), now: codexNow) {
    expect(limits.map(\.label) == ["Week"], "codex labels: \(limits.map(\.label))")
    expect(limits.first?.percent == 69, "codex uses the newest event: \(limits.map(\.percent))")
    expect(limits.first?.kind == .weekly, "codex weekly kind")
    expect(limits.first?.resetsAt == Date(timeIntervalSince1970: 1790610676), "codex reset from unix seconds")
} else {
    expect(false, "codex log had no limits")
}

// Plus plan: a 5 hour primary and a weekly secondary, listed session first.
let plus = #"{"limit_id":"codex","primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1790450000},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1790610676},"plan_type":"plus"}"#
let plusLimits = CodexParser.latestLimits(inLog: Data(codexEvent(plus).utf8), now: codexNow) ?? []
expect(plusLimits.map(\.label) == ["Session", "Week"], "plus labels: \(plusLimits.map(\.label))")
expect(plusLimits.map(\.kind) == [.session, .weekly], "plus kinds")
expect(plusLimits.map(\.percent) == [12.5, 40], "plus percents")

// A window whose reset passed shows 0% until Codex logs again.
let afterReset = Date(timeIntervalSince1970: 1790610677)
let reset = CodexParser.latestLimits(inLog: Data(codexEvent(prolite).utf8), now: afterReset) ?? []
expect(reset.first?.percent == 0 && reset.first?.resetsAt == nil, "passed reset shows 0%: \(reset)")

// An event without limits, or from another pool, falls back to the one before it.
let fallbackLog = [codexEvent(prolite), codexEvent("null"),
                   codexEvent(#"{"limit_id":"premium","primary":{"used_percent":99,"window_minutes":10080}}"#)]
    .joined(separator: "\n")
expect(CodexParser.latestLimits(inLog: Data(fallbackLog.utf8), now: codexNow)?.first?.percent == 69,
       "skips null and premium events")
// An event with no windows falls back too, instead of hiding Codex.
let noWindows = [codexEvent(prolite), codexEvent(#"{"limit_id":"codex","primary":null,"secondary":null}"#)]
    .joined(separator: "\n")
expect(CodexParser.latestLimits(inLog: Data(noWindows.utf8), now: codexNow)?.first?.percent == 69,
       "skips an event without windows")
expect(CodexParser.latestLimits(inLog: Data(codexLog.prefix(80).utf8), now: codexNow) == nil, "no event is nil")
expect(CodexParser.latestLimits(inLog: Data(), now: codexNow) == nil, "empty log is nil")
expect(CodexParser.label(minutes: 1440) == "1d" && CodexParser.label(minutes: 120) == "2h", "other window labels")

// Codex: the newest logs by modification date, wherever their day folder is.
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("codex-sessions-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    func log(_ path: String, modified: TimeInterval) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
        return url
    }
    let resumed = try log("2026/09/01/rollout-resumed.jsonl", modified: 3000)
    let today = try log("2026/09/26/rollout-today.jsonl", modified: 2000)
    _ = try log("2026/09/25/rollout-yesterday.jsonl", modified: 1000)
    _ = try log("2026/09/26/notes.txt", modified: 4000)
    let newest = CodexParser.newestLogs(in: root, limit: 2).map(\.lastPathComponent)
    expect(newest == [resumed.lastPathComponent, today.lastPathComponent], "newest logs: \(newest)")
    expect(CodexParser.newestLogs(in: root.appendingPathComponent("missing"), limit: 5).isEmpty, "no sessions folder")
    let empty = root.appendingPathComponent("empty")
    try fm.createDirectory(at: empty, withIntermediateDirectories: true)
    expect(CodexParser.newestLogs(in: empty, limit: 5).isEmpty, "empty sessions folder")

    // A symlink named *.jsonl is not followed, so no file outside the logs is read.
    let outside = root.appendingPathComponent("outside.json")
    try Data(codexEvent(prolite).utf8).write(to: outside)
    let link = root.appendingPathComponent("2026/09/26/rollout-link.jsonl")
    try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    expect(!CodexParser.newestLogs(in: root, limit: 10).map(\.lastPathComponent).contains("rollout-link.jsonl"),
           "symlinked log skipped")
    // Neither a folder named *.jsonl nor a link to a missing file is a log.
    try fm.createDirectory(at: root.appendingPathComponent("2026/09/26/rollout-folder.jsonl"), withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: root.appendingPathComponent("2026/09/26/rollout-broken.jsonl"),
                              withDestinationURL: root.appendingPathComponent("gone.json"))
    let names = CodexParser.newestLogs(in: root, limit: 10).map(\.lastPathComponent)
    expect(!names.contains("rollout-folder.jsonl") && !names.contains("rollout-broken.jsonl"),
           "folders and broken links skipped: \(names)")
} catch {
    expect(false, "codex log lookup threw \(error)")
}

// Codex: the newest log without limits falls back to the next newest one.
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("codex-read-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    let day = root.appendingPathComponent("2026/09/26")
    try fm.createDirectory(at: day, withIntermediateDirectories: true)
    let older = day.appendingPathComponent("rollout-older.jsonl")
    let newer = day.appendingPathComponent("rollout-newer.jsonl")
    // The older log ends in a line Codex is still writing.
    try Data((codexLog + #"{"timestamp":"2026-09-26T17:04:00Z","type":"event_msg","payload":{"type":"token_count","rate_"#).utf8)
        .write(to: older)
    try Data(#"{"type":"session_meta","payload":{"id":"new"}}"#.utf8).write(to: newer)
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: older.path)
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: newer.path)
    let limits = CodexParser.latestLimits(inSessions: root, logs: 5, now: codexNow)
    expect(limits?.first?.percent == 69, "falls back to the older log past a partial line: \(String(describing: limits))")
    expect(CodexParser.latestLimits(inSessions: root, logs: 1, now: codexNow) == nil, "stops after the log limit")
} catch {
    expect(false, "codex log lookup threw \(error)")
}

// Snapshots written before Codex support still load, without Codex.
do {
    let old = #"{"limits":[],"fetchedAt":"2026-09-26T17:00:00Z"}"#
    let decoded = try SnapshotStore.decoder.decode(UsageSnapshot.self, from: Data(old.utf8))
    expect(decoded.codex == nil, "old snapshot has no codex")
    let data = try SnapshotStore.encoder.encode(UsageSnapshot.placeholder)
    let back = try SnapshotStore.decoder.decode(UsageSnapshot.self, from: data)
    expect(back.codex?.map(\.percent) == [69], "codex round-trip")
} catch {
    expect(false, "codex snapshot threw \(error)")
}

// Menu bar: each tool's tightest limit, Codex only when present.
expect(UsageSnapshot.menuBarTitle(for: nil) == "Claude --", "menu bar before first fetch")
expect(UsageSnapshot.menuBarTitle(for: .placeholder) == "Claude 64% · Codex 69%",
       "menu bar both: \(UsageSnapshot.menuBarTitle(for: .placeholder))")
var claudeOnly = UsageSnapshot.placeholder
claudeOnly.codex = []
expect(UsageSnapshot.menuBarTitle(for: claudeOnly) == "Claude 64%", "menu bar without codex")
claudeOnly.limits = []
claudeOnly.codex = UsageSnapshot.placeholder.codex
expect(UsageSnapshot.menuBarTitle(for: claudeOnly) == "Claude -- · Codex 69%", "menu bar signed out of claude")

if failures == 0 {
    print("All parser tests passed")
} else {
    print("\(failures) failure(s)")
    exit(1)
}
