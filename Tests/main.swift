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

if failures == 0 {
    print("All parser tests passed")
} else {
    print("\(failures) failure(s)")
    exit(1)
}
