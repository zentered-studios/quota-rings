import SwiftUI

// Pure SwiftUI views, free of WidgetKit so scripts/render.sh can snapshot them to PNG.

enum Palette {
    static let session = Color(red: 0.91, green: 0.47, blue: 0.36)   // coral
    static let week = Color(red: 0.96, green: 0.73, blue: 0.32)      // amber
    static let model = Color(red: 0.66, green: 0.55, blue: 0.98)     // violet
    static let critical = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let backgroundTop = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let backgroundBottom = Color(red: 0.17, green: 0.12, blue: 0.10)
    static let secondary = Color.white.opacity(0.55)

    static func color(for limit: UsageLimit) -> Color {
        switch limit.kind {
        case .session: return session
        case .weekly: return week
        case .model: return model
        }
    }
}

struct WidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop, Palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.session.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 190)
            RadialGradient(colors: [Palette.model.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 170)
        }
    }
}

enum WidgetSize { case small, medium }

struct UsageWidgetContent: View {
    let size: WidgetSize
    let snapshot: UsageSnapshot?
    let now: Date

    /// Snapshots older than this are marked stale, e.g. when the agent is not running.
    static let staleAfter: TimeInterval = 20 * 60

    var body: some View {
        Group {
            if let snapshot, !snapshot.limits.isEmpty {
                let limits = Array(snapshot.limits.prefix(3))
                VStack(alignment: .leading, spacing: 0) {
                    Header(snapshot: snapshot, now: now, showUpdated: size == .medium)
                    Spacer(minLength: 10)
                    switch size {
                    case .small: SmallLayout(limits: limits, now: now)
                    case .medium: MediumLayout(limits: limits, now: now)
                    }
                    Spacer(minLength: 4)
                    if size == .medium, let error = snapshot.error {
                        Text(error)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.critical)
                            .lineLimit(1)
                    }
                }
            } else {
                EmptyState(message: snapshot?.error)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct Header: View {
    let snapshot: UsageSnapshot
    let now: Date
    let showUpdated: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.session)
            Text("CLAUDE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
            Spacer(minLength: 4)
            if snapshot.error != nil || now.timeIntervalSince(snapshot.fetchedAt) > UsageWidgetContent.staleAfter {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.week)
            }
            if showUpdated {
                Text(shortAge(since: snapshot.fetchedAt, now: now))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

// MARK: - Small: concentric rings beside a stacked legend

private struct SmallLayout: View {
    let limits: [UsageLimit]
    let now: Date

    /// The limit closest to running out. Its reset time is the one worth showing.
    private var tightest: UsageLimit? { limits.max { $0.percent < $1.percent } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ConcentricRings(limits: limits)
                    .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(limits) { limit in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(limit.label.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(Palette.color(for: limit))
                                .lineLimit(1)
                            PercentText(limit: limit, size: 15)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let tightest, let reset = tightest.resetsAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(tightest.label) resets in \(shortDuration(from: now, to: reset))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Palette.secondary)
            }
        }
    }
}

private struct ConcentricRings: View {
    let limits: [UsageLimit]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.1
            let gap = line * 0.55
            ZStack {
                ForEach(Array(limits.enumerated()), id: \.element.id) { index, limit in
                    let inset = CGFloat(index) * (line + gap)
                    Ring(progress: limit.percent / 100, color: Palette.color(for: limit), lineWidth: line, glow: false)
                        .padding(inset + line / 2)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

// MARK: - Medium: one gauge per limit

private struct MediumLayout: View {
    let limits: [UsageLimit]
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(limits) { limit in
                VStack(spacing: 9) {
                    ZStack {
                        Ring(progress: limit.percent / 100, color: Palette.color(for: limit), lineWidth: 7)
                        PercentText(limit: limit, size: 16)
                    }
                    .frame(width: 60, height: 60)
                    VStack(spacing: 2) {
                        Text(limit.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if let reset = limit.resetsAt {
                            Text("resets in \(shortDuration(from: now, to: reset))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Building blocks

struct Ring: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    var glow = true

    var body: some View {
        let p = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(p, 0.001))
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.75), color],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(p, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(glow ? 0.55 : 0), radius: lineWidth * 0.6)
        }
    }
}

private struct PercentText: View {
    let limit: UsageLimit
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(Int(limit.percent.rounded()))")
                .font(.system(size: size, weight: .bold, design: .rounded))
            Text("%")
                .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .foregroundStyle(limit.severity == "critical" ? Palette.critical.opacity(0.8) : Palette.secondary)
        }
        .monospacedDigit()
        .foregroundStyle(limit.severity == "critical" ? Palette.critical : .white)
    }
}

private struct EmptyState: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle").foregroundStyle(Palette.session)
                Text("CLAUDE").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.6)
            }
            .font(.system(size: 11, weight: .bold))
            Spacer(minLength: 0)
            Text(message ?? "Click to start fetching usage.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Formatting

/// "3h 28m", "4d 20h", "12m".
func shortDuration(from now: Date, to date: Date) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
    let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(mins)m"
}

func shortAge(since date: Date, now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m ago" }
    return "\(minutes / 60)h ago"
}
