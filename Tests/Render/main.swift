import AppKit
import SwiftUI

// Renders the widget views to PNG for a visual check. Run with scripts/render.sh.

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/render", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let live = SnapshotStore.load()
var stale = UsageSnapshot.placeholder
stale.error = "Token expired. Run `claude` once to refresh it."

let cases: [(String, WidgetSize, UsageSnapshot?, CGSize)] = [
    ("small", .small, live ?? .placeholder, CGSize(width: 170, height: 170)),
    ("medium", .medium, live ?? .placeholder, CGSize(width: 364, height: 170)),
    ("medium-error", .medium, stale, CGSize(width: 364, height: 170)),
    ("small-empty", .small, nil, CGSize(width: 170, height: 170)),
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
