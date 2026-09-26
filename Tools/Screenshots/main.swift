import AppKit
import SwiftUI

// Renders 2880x1800 marketing screenshots into docs/screenshots. Run with scripts/screenshots.sh.
// Uses fixed sample numbers so every render is identical.

let now = Date()
let sample = UsageSnapshot(
    limits: [
        UsageLimit(kind: .session, label: "Session", percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60), severity: "normal"),
        UsageLimit(kind: .weekly, label: "Week", percent: 71, resetsAt: now.addingTimeInterval(3 * 86400 + 6 * 3600), severity: "warning"),
        UsageLimit(kind: .model, label: "Fable", percent: 38, resetsAt: now.addingTimeInterval(3 * 86400 + 6 * 3600), severity: "normal"),
    ],
    fetchedAt: now.addingTimeInterval(-60),
    codex: [
        UsageLimit(kind: .session, label: "Session", percent: 18, resetsAt: now.addingTimeInterval(3 * 3600 + 40 * 60), severity: "normal"),
        UsageLimit(kind: .weekly, label: "Week", percent: 55, resetsAt: now.addingTimeInterval(2 * 86400 + 9 * 3600), severity: "normal"),
    ]
)
var critical = sample
critical.limits[1].percent = 96
critical.limits[1].severity = "critical"
var expired = sample
expired.status = .expired

struct WidgetCard: View {
    let size: WidgetSize
    let snapshot: UsageSnapshot?
    let scale: CGFloat

    var body: some View {
        let frame = size == .small ? CGSize(width: 170, height: 170) : CGSize(width: 364, height: 170)
        UsageWidgetContent(size: size, snapshot: snapshot, now: now)
            .padding(16)
            .frame(width: frame.width, height: frame.height)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .scaleEffect(scale)
            .frame(width: frame.width * scale, height: frame.height * scale)
            .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
    }
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.10, blue: 0.10), Color(red: 0.06, green: 0.06, blue: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Palette.session.opacity(0.30), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0, endRadius: 800)
            RadialGradient(colors: [Palette.model.opacity(0.22), .clear], center: UnitPoint(x: 0.9, y: 0.95), startRadius: 0, endRadius: 800)
        }
    }
}

struct Headline: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
            Text(subtitle)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
    }
}

/// A menu bar strip with the app's item and its open menu, drawn with the real icon.
struct MenuBarMock: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 18) {
                Spacer()
                Text(UsageSnapshot.menuBarTitle(for: sample)).font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "wifi").font(.system(size: 14))
                Image(systemName: "battery.75percent").font(.system(size: 16))
                Text("Thu 9:41").font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(.black.opacity(0.35))
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 7) {
                Text("Claude").foregroundStyle(.white.opacity(0.5))
                ForEach(sample.limits) { limit in
                    Text("\(limit.label): \(Int(limit.percent))%  (resets in \(shortDuration(from: now, to: limit.resetsAt!)))")
                }
                Text("Codex").foregroundStyle(.white.opacity(0.5))
                ForEach(sample.codex ?? []) { limit in
                    Text("\(limit.label): \(Int(limit.percent))%  (resets in \(shortDuration(from: now, to: limit.resetsAt!)))")
                }
                Text("Updated 9:40").foregroundStyle(.white.opacity(0.5))
                Divider().overlay(.white.opacity(0.2))
                Text("Refresh Now")
                Text("✓ Open at Login")
                Divider().overlay(.white.opacity(0.2))
                Text("Quit Quota Rings")
            }
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(14)
            .frame(width: 330, alignment: .leading)
            .background(Color(white: 0.16).opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            .padding(.trailing, 150)
        }
    }
}

let screens: [(String, AnyView)] = [
    ("01-at-a-glance", AnyView(
        VStack(spacing: 70) {
            Headline(title: "Your plan limits, at a glance.",
                     subtitle: "Session, weekly and per-model usage on your desktop. Works with Claude Code.")
            HStack(alignment: .center, spacing: 50) {
                WidgetCard(size: .medium, snapshot: sample, scale: 2)
                WidgetCard(size: .small, snapshot: sample, scale: 2)
            }
        }
    )),
    ("02-know-when-it-resets", AnyView(
        VStack(spacing: 70) {
            Headline(title: "See the wall before you hit it.",
                     subtitle: "Numbers turn red near the limit, with a countdown to the next reset.")
            HStack(alignment: .center, spacing: 50) {
                WidgetCard(size: .small, snapshot: critical, scale: 2.2)
                WidgetCard(size: .medium, snapshot: critical, scale: 2.2)
            }
        }
    )),
    ("03-menu-bar", AnyView(
        VStack(spacing: 0) {
            MenuBarMock()
            Spacer()
            Headline(title: "Also in your menu bar.",
                     subtitle: "Updates every 5 minutes, after wake, and when you click the widget.")
            Spacer()
        }
        .padding(.bottom, 120)
    )),
    ("04-always-honest", AnyView(
        VStack(spacing: 70) {
            Headline(title: "Clear about what it knows.",
                     subtitle: "Out-of-date numbers dim and tell you how to reconnect.")
            HStack(alignment: .center, spacing: 50) {
                WidgetCard(size: .medium, snapshot: expired, scale: 2)
                WidgetCard(size: .small, snapshot: UsageSnapshot(limits: [], fetchedAt: now, status: .notSignedIn), scale: 2)
            }
        }
    )),
]

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/screenshots", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

try MainActor.assumeIsolated {
    for (name, content) in screens {
        let view = ZStack {
            Backdrop()
            content
        }
        .frame(width: 1440, height: 900)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw NSError(domain: "screenshots", code: 1) }
        let url = outDir.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print(url.path)
    }
}
