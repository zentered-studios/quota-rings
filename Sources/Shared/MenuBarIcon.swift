import AppKit

/// Menu bar icon: three concentric rings that fill with the real usage.
/// Outer is the session limit, middle the weekly limit, inner the first model-scoped limit.
/// Drawn as a template image so it follows the menu bar's light or dark tint.
@MainActor
enum MenuBarIcon {
    private static let radii: [CGFloat] = [7.4, 4.9, 2.4]
    private static let lineWidth: CGFloat = 1.8

    private static var cache: [[Int]: NSImage] = [:]

    static func image(for limits: [UsageLimit]) -> NSImage {
        let kinds: [UsageLimit.Kind] = [.session, .weekly, .model]
        // Whole percents are as fine as 18pt can show, and keep the cache small.
        let percents = kinds.map { kind in
            limits.first { $0.kind == kind }.map { Int(min(max($0.percent, 0), 100).rounded()) } ?? 0
        }
        if let cached = cache[percents] { return cached }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            for (radius, percent) in zip(radii, percents) {
                let track = NSBezierPath()
                track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                track.lineWidth = lineWidth
                NSColor.black.withAlphaComponent(0.25).setStroke()
                track.stroke()

                guard percent > 0 else { continue }
                // Clockwise from 12 o'clock, like the widget rings.
                let sweep = 360 * CGFloat(percent) / 100
                let arc = NSBezierPath()
                if percent >= 100 {
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                } else {
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - sweep, clockwise: true)
                }
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Session \(percents[0])%, week \(percents[1])%, model \(percents[2])%"
        cache[percents] = image
        return image
    }
}
