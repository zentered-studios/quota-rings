import AppKit
import SwiftUI

// Renders the widget views to PNG for a visual check. Run with scripts/render.sh.

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/render", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var data = SnapshotStore.load().flatMap { $0.limits.isEmpty ? nil : $0 } ?? .placeholder
data.status = nil
if data.codex == nil { data.codex = UsageSnapshot.placeholder.codex }

func withStatus(_ status: UsageStatus, keepLimits: Bool) -> UsageSnapshot {
    var s = data
    s.status = status
    if !keepLimits { s.limits = [] }
    return s
}

func variant(_ change: (inout UsageSnapshot) -> Void) -> UsageSnapshot {
    var s = data
    change(&s)
    return s
}

let small = CGSize(width: 170, height: 170)
let medium = CGSize(width: 364, height: 170)

let cases: [(String, WidgetSize, UsageSnapshot?, CGSize)] = [
    ("small", .small, data, small),
    ("medium", .medium, data, medium),
    ("small-expired", .small, withStatus(.expired, keepLimits: true), small),
    ("medium-expired", .medium, withStatus(.expired, keepLimits: true), medium),
    ("small-offline", .small, withStatus(.offline, keepLimits: true), small),
    ("small-not-signed-in", .small, withStatus(.notSignedIn, keepLimits: false), small),
    ("medium-not-signed-in", .medium, withStatus(.notSignedIn, keepLimits: false), medium),
    ("small-no-plan", .small, withStatus(.noPlan, keepLimits: false), small),
    ("small-expired-empty", .small, withStatus(.expired, keepLimits: false), small),
    ("small-claude-only", .small, variant { $0.codex = nil }, small),
    ("medium-claude-only", .medium, variant { $0.codex = nil }, medium),
    ("small-critical", .small, variant { $0.codex?[0].percent = 97; $0.limits[0].percent = 84 }, small),
    ("medium-critical", .medium, variant { $0.codex?[0].percent = 97; $0.limits[0].percent = 84 }, medium),
    ("small-stale", .small, variant { $0.fetchedAt = Date().addingTimeInterval(-3600) }, small),
    ("small-not-signed-in-codex", .small, variant { $0.limits = []; $0.status = .notSignedIn }, small),
    ("medium-not-signed-in-codex", .medium, variant { $0.limits = []; $0.status = .notSignedIn }, medium),
    ("small-not-running", .small, nil, small),
    ("medium-not-running", .medium, nil, medium),
]

/// The menu bar icon at several usage levels, on light and dark bars, scaled up 6x.
struct MenuBarIconSheet: View {
    let levels: [[Double]] = [[0, 0, 0], [15, 64, 29], [42, 71, 38], [97, 99, 30], [100, 100, 100]]

    var body: some View {
        VStack(spacing: 0) {
            ForEach([Color.white, Color.black], id: \.self) { bar in
                HStack(spacing: 24) {
                    ForEach(levels.indices, id: \.self) { i in
                        let l = levels[i]
                        let limits = [
                            UsageLimit(kind: .session, label: "Session", percent: l[0], resetsAt: nil, severity: "normal"),
                            UsageLimit(kind: .weekly, label: "Week", percent: l[1], resetsAt: nil, severity: "normal"),
                            UsageLimit(kind: .model, label: "Model", percent: l[2], resetsAt: nil, severity: "normal"),
                        ]
                        Image(nsImage: MenuBarIcon.image(for: limits))
                            .renderingMode(.template)
                            .foregroundStyle(bar == .white ? Color.black : Color.white)
                    }
                }
                .padding(8)
                .background(bar)
            }
        }
    }
}

@MainActor func render() throws {
    let icons = ImageRenderer(content: MenuBarIconSheet())
    icons.scale = 6
    if let tiff = icons.nsImage?.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try png.write(to: outDir.appendingPathComponent("menubar-icon.png"))
    }

    for (name, size, snapshot, frame) in cases {
        let view = UsageWidgetContent(size: size, snapshot: snapshot, now: Date())
            .padding(16)
            .frame(width: frame.width, height: frame.height)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw NSError(domain: "render", code: 1) }
        let url = outDir.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print(url.path)
    }
}

try MainActor.assumeIsolated { try render() }
