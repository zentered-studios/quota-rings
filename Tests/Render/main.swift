import AppKit
import SwiftUI

// Renders the widget views to PNG for a visual check. Run with scripts/render.sh.

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/render", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let data = SnapshotStore.load().flatMap { $0.limits.isEmpty ? nil : $0 } ?? .placeholder

func withStatus(_ status: UsageStatus, keepLimits: Bool) -> UsageSnapshot {
    var s = data
    s.status = status
    if !keepLimits { s.limits = [] }
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
    ("small-not-running", .small, nil, small),
    ("medium-not-running", .medium, nil, medium),
]

@MainActor func render() throws {
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
