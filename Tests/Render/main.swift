import AppKit
import SwiftUI

// Renders the widget views to PNG for a visual check. Run with scripts/render.sh.

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/render", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var data = SnapshotStore.load().flatMap { $0.limits.isEmpty ? nil : $0 } ?? .placeholder
data.status = nil
if data.codex == nil { data.codex = UsageSnapshot.placeholder.codex }

func variant(_ change: (inout UsageSnapshot) -> Void) -> UsageSnapshot {
    var s = data
    change(&s)
    return s
}

func withStatus(_ status: UsageStatus, keepLimits: Bool) -> UsageSnapshot {
    variant {
        $0.status = status
        if !keepLimits { $0.limits = [] }
    }
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

/// Menu bar titles for several states, on light and dark bars, scaled up 3x.
struct MenuBarSheet: View {
    let titles = [
        UsageSnapshot.menuBarTitle(for: data),
        UsageSnapshot.menuBarTitle(for: variant { $0.codex = nil }),
        UsageSnapshot.menuBarTitle(for: variant { $0.limits = [] }),
        UsageSnapshot.menuBarTitle(for: nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach([Color.white, Color.black], id: \.self) { bar in
                HStack(spacing: 24) {
                    ForEach(titles, id: \.self) { title in
                        Text(title).font(.system(size: 13, weight: .medium))
                    }
                }
                .foregroundStyle(bar == .white ? Color.black : Color.white)
                .padding(8)
                .background(bar)
            }
        }
    }
}

@MainActor func render() throws {
    let icons = ImageRenderer(content: MenuBarSheet())
    icons.scale = 3
    if let tiff = icons.nsImage?.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try png.write(to: outDir.appendingPathComponent("menubar.png"))
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
