import AppKit
import SwiftUI

// Renders the app icon into Sources/App/Assets.xcassets/AppIcon.appiconset. Run with scripts/icon.sh.

struct AppIconView: View {
    // Apple's macOS icon grid: 1024pt canvas, 824pt body, ~185pt corner radius.
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.19, green: 0.14, blue: 0.12), Color(red: 0.08, green: 0.07, blue: 0.07)],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    RadialGradient(colors: [Palette.session.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 620)
                        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                )
                .overlay(
                    RadialGradient(colors: [Palette.model.opacity(0.22), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
                .frame(width: 824, height: 824)

            ZStack {
                ring(Palette.session, progress: 0.78, inset: 0)
                ring(Palette.week, progress: 0.62, inset: 1)
                ring(Palette.model, progress: 0.40, inset: 2)
            }
            .frame(width: 540, height: 540)
        }
        .frame(width: 1024, height: 1024)
    }

    private func ring(_ color: Color, progress: Double, inset: Int) -> some View {
        let line: CGFloat = 54
        return Ring(progress: progress, color: color, lineWidth: line, glow: false)
            .padding(line / 2 + CGFloat(inset) * line * 1.75)
            .shadow(color: color.opacity(0.35), radius: 10)
    }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

@MainActor func png(pixels: Int) throws -> Data {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = CGFloat(pixels) / 1024
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { throw NSError(domain: "icon", code: 1) }
    return data
}

var images: [[String: String]] = []
try MainActor.assumeIsolated {
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try png(pixels: points * scale).write(to: outDir.appendingPathComponent(name))
            images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
