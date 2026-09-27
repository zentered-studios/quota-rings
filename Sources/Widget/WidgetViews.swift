import SwiftUI

// Pure SwiftUI views, free of WidgetKit so scripts/render.sh can snapshot them to PNG.

enum Palette {
    static let claude = Color(red: 0.91, green: 0.47, blue: 0.36)    // coral
    static let codex = Color(red: 0.56, green: 0.71, blue: 0.91)     // blue
    static let warning = Color(red: 0.96, green: 0.73, blue: 0.32)   // amber
    static let critical = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let secondary = Color.white.opacity(0.55)
    static let track = Color.white.opacity(0.12)

    // The rings in the app icon and screenshots.
    static let session = claude
    static let week = warning
    static let model = Color(red: 0.66, green: 0.55, blue: 0.98)     // violet

    /// The tool color until the limit gets close, then amber and red.
    static func fill(for limit: UsageLimit, tool: Color) -> Color {
        switch limit.level {
        case .normal: return tool
        case .warning: return warning
        case .critical: return critical
        }
    }
}

struct WidgetBackground: View {
    var body: some View { Palette.background }
}

enum WidgetSize { case small, medium }

/// One tool's limits as the widget draws them.
struct ToolUsage: Identifiable {
    let name: String
    let color: Color
    let limits: [UsageLimit]
    /// Why the last fetch failed. Only Claude has one; Codex reads local files.
    var status: UsageStatus? = nil

    var id: String { name }
}

struct UsageWidgetContent: View {
    let size: WidgetSize
    let snapshot: UsageSnapshot?
    let now: Date

    /// Snapshots older than this are marked stale, e.g. when the agent is not running.
    static let staleAfter: TimeInterval = 20 * 60
    /// Opacity for old numbers shown next to a status, so they read as out of date.
    static let dimmed: Double = 0.45

    /// Claude always has a slot so its status stays visible. Codex only when it logged limits.
    private var tools: [ToolUsage] {
        guard let snapshot else { return [] }
        var tools = [ToolUsage(name: "Claude", color: Palette.claude, limits: snapshot.limits, status: snapshot.status)]
        if let codex = snapshot.codex, !codex.isEmpty {
            tools.append(ToolUsage(name: "Codex", color: Palette.codex, limits: codex))
        }
        return tools
    }

    var body: some View {
        Group {
            if let snapshot, !snapshot.limits.isEmpty || snapshot.codex?.isEmpty == false {
                let stale = now.timeIntervalSince(snapshot.fetchedAt) > Self.staleAfter
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    switch size {
                    case .small: SmallLayout(tools: tools, now: now)
                    case .medium: MediumLayout(tools: tools, now: now)
                    }
                    Spacer(minLength: 0)
                    if size == .medium, let status = snapshot.status {
                        StatusLine(symbol: status.symbol, text: "Claude: \(status.title) · \(status.detail)")
                    } else if stale && snapshot.status == nil {
                        StatusLine(symbol: "exclamationmark.triangle.fill",
                                   text: "Updated \(shortAge(since: snapshot.fetchedAt, now: now))")
                    }
                }
            } else {
                EmptyState(size: size, info: StateInfo(snapshot: snapshot))
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// Icon, title and next step for a widget that has no numbers to show.
struct StateInfo {
    let symbol: String
    let title: String
    let detail: String

    init(snapshot: UsageSnapshot?) {
        if let status = snapshot?.status {
            symbol = status.symbol
            title = status.title
            detail = status.detail
        } else if snapshot == nil {
            symbol = "power"
            title = "Not running"
            detail = "Click to start Quota Rings."
        } else {
            symbol = "hourglass"
            title = "Loading"
            detail = "Fetching your usage."
        }
    }
}

private struct StatusLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Palette.warning)
    }
}

// MARK: - Small: each tool's tightest limit

private struct SmallLayout: View {
    let tools: [ToolUsage]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(tools) { tool in
                ToolSummary(tool: tool, now: now)
            }
        }
    }
}

private struct ToolSummary: View {
    let tool: ToolUsage
    let now: Date

    var body: some View {
        let tightest = tool.limits.tightest
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tool.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer(minLength: 4)
                    if let tightest {
                        PercentText(limit: tightest, size: 20)
                    } else {
                        Text("--").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
                Bar(limit: tightest, tool: tool.color, height: 6)
            }
            .opacity(tool.status == nil ? 1 : UsageWidgetContent.dimmed)
            if let status = tool.status {
                Text(status.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.warning)
                    .lineLimit(1)
            } else if let tightest {
                Text(resetLabel(tightest, now: now))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Medium: one column per tool, one bar per limit

private struct MediumLayout: View {
    let tools: [ToolUsage]
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: 10) {
                    Text(tool.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    if tool.limits.isEmpty, let status = tool.status {
                        Text(status.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.warning)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(tool.limits.prefix(3)) { limit in
                            LimitRow(limit: limit, tool: tool.color, now: now)
                        }
                    }
                    .opacity(tool.status == nil ? 1 : UsageWidgetContent.dimmed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit
    let tool: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(limit.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                if let reset = limit.resetsAt {
                    Text(shortDuration(from: now, to: reset))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 4)
                PercentText(limit: limit, size: 13)
            }
            .lineLimit(1)
            Bar(limit: limit, tool: tool, height: 4)
        }
    }
}

// MARK: - Building blocks

struct Bar: View {
    let limit: UsageLimit?
    let tool: Color
    let height: CGFloat

    var body: some View {
        let p = min(max((limit?.percent ?? 0) / 100, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                if let limit, p > 0 {
                    Capsule()
                        .fill(Palette.fill(for: limit, tool: tool))
                        .frame(width: max(geo.size.width * p, height))
                }
            }
        }
        .frame(height: height)
    }
}

private struct PercentText: View {
    let limit: UsageLimit
    let size: CGFloat

    var body: some View {
        let critical = limit.level == .critical
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(Int(limit.percent.rounded()))")
                .font(.system(size: size, weight: .bold, design: .rounded))
            Text("%")
                .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                .foregroundStyle(critical ? Palette.critical.opacity(0.8) : Palette.secondary)
        }
        .monospacedDigit()
        .foregroundStyle(critical ? Palette.critical : .white)
    }
}

/// No numbers to show: the state's icon, a title and the next step.
private struct EmptyState: View {
    let size: WidgetSize
    let info: StateInfo

    var body: some View {
        Group {
            switch size {
            case .small:
                VStack(alignment: .leading, spacing: 10) {
                    icon
                    text
                }
            case .medium:
                HStack(spacing: 16) {
                    icon
                    text
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var icon: some View {
        Image(systemName: info.symbol)
            .font(.system(size: size == .small ? 22 : 28, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(info.title)
                .font(.system(size: size == .small ? 14 : 16, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(info.detail)
                .font(.system(size: size == .small ? 10.5 : 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Formatting

/// "Session · 3h 6m", or the label alone when the reset time is unknown.
func resetLabel(_ limit: UsageLimit, now: Date) -> String {
    guard let reset = limit.resetsAt else { return limit.label }
    return "\(limit.label) · \(shortDuration(from: now, to: reset))"
}

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
