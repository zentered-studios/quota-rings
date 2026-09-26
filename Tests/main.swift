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

// claude.ai: the plan organization is the one with the chat capability.
let orgs = ClaudeWebParsing.organizations(from: Data(#"""
[
  {"uuid": "api-org", "name": "API", "capabilities": ["api"]},
  {"uuid": "chat-org", "name": "Personal", "capabilities": ["chat", "claude_max"]},
  {"name": "no id"}
]
"""#.utf8))
expect(orgs.count == 2, "orgs without uuid are skipped: \(orgs.count)")
expect(ClaudeWebParsing.planOrganization(in: orgs)?.id == "chat-org", "picks chat org")
expect(ClaudeWebParsing.planOrganization(in: [orgs[0]]) == nil, "API-only org has no plan limits")
expect(ClaudeWebParsing.planOrganization(in: ClaudeWebParsing.organizations(from: Data(#"[{"uuid":"x"}]"#.utf8)))?.id == "x",
       "org without capabilities is still used")
expect(ClaudeWebParsing.organizations(from: Data("<html>".utf8)).isEmpty, "HTML is not an org list")
// The id goes into a URL path, so anything but UUID characters is rejected.
let unsafeOrgs = ClaudeWebParsing.organizations(from: Data(#"""
[{"uuid": "../../account", "capabilities": ["chat"]}, {"uuid": "a1b2-c3?x=1", "capabilities": ["chat"]},
 {"uuid": "0f8e2c1a-9b7d-4e6f-a5c3-2d1e0f9a8b7c", "capabilities": ["chat"]}]
"""#.utf8))
expect(unsafeOrgs.map(\.id) == ["0f8e2c1a-9b7d-4e6f-a5c3-2d1e0f9a8b7c"], "unsafe org ids skipped: \(unsafeOrgs.map(\.id))")

// claude.ai: only claude.ai and its subdomains may supply the session cookie.
for domain in ["claude.ai", ".claude.ai", "www.claude.ai", "CLAUDE.AI", ".Claude.ai"] {
    expect(ClaudeWebParsing.isClaudeCookieDomain(domain), "\(domain) is claude.ai")
}
for domain in ["evilclaude.ai", ".notclaude.ai", "claude.ai.example.com", ""] {
    expect(!ClaudeWebParsing.isClaudeCookieDomain(domain), "\(domain) is not claude.ai")
}

// claude.ai: Cloudflare challenge vs. a real auth failure.
expect(ClaudeWebParsing.isCloudflareChallenge(status: 403, contentType: "text/html; charset=UTF-8", body: Data()),
       "403 HTML is a challenge")
expect(!ClaudeWebParsing.isCloudflareChallenge(status: 403, contentType: "application/json",
                                               body: Data(#"{"error":"permission_error"}"#.utf8)),
       "403 JSON is an auth failure")
expect(!ClaudeWebParsing.isCloudflareChallenge(status: 401, contentType: "text/html", body: Data()), "401 is never a challenge")

// claude.ai: a rotated sessionKey in Set-Cookie is picked up.
let claudeURL = URL(string: "https://claude.ai/api/organizations")!
expect(ClaudeWebParsing.renewedSessionKey(
    headers: ["Set-Cookie": "sessionKey=sk-new; Domain=.claude.ai; Path=/; Secure; HttpOnly"], url: claudeURL) == "sk-new",
    "renewed session key")
expect(ClaudeWebParsing.renewedSessionKey(headers: ["Set-Cookie": "other=1; Path=/"], url: claudeURL) == nil,
       "unrelated cookie ignored")
expect(ClaudeWebParsing.renewedSessionKey(
    headers: ["Set-Cookie": "sessionKey=sk-evil; Path=/"], url: URL(string: "https://evilclaude.ai/x")!) == nil,
    "session key from another host ignored")

// Credential sessions refuse redirects: the delegate answers nil for any redirect target.
do {
    let original = URL(string: "https://claude.ai/api/organizations")!
    let task = URLSession(configuration: .ephemeral).dataTask(with: original) // never resumed, no network
    let redirect = HTTPURLResponse(url: original, statusCode: 302, httpVersion: "HTTP/1.1",
                                   headerFields: ["Location": "https://example.com/"])!
    var request = URLRequest(url: URL(string: "https://example.com/")!)
    request.setValue("sessionKey=secret", forHTTPHeaderField: "Cookie")
    var followed: URLRequest?? = .none
    NoRedirectDelegate().urlSession(URLSession.credentialSession(), task: task, willPerformHTTPRedirection: redirect,
                                    newRequest: request) { followed = .some($0) }
    expect(followed != nil, "delegate answered")
    expect(followed! == nil, "redirect refused, cookie not forwarded")
}

// The claude.ai source can override the widget's next-step text.
var webSnapshot = UsageSnapshot(limits: [], fetchedAt: Date(), status: .expired)
expect(webSnapshot.detailText == UsageStatus.expired.detail, "default detail")
webSnapshot.statusDetail = "Sign in to claude.ai again from the menu bar."
expect(webSnapshot.detailText == "Sign in to claude.ai again from the menu bar.", "override detail")

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
