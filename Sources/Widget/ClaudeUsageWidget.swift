import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = context.isPreview ? (SnapshotStore.load() ?? .placeholder) : SnapshotStore.load()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The host app pushes reloads after each fetch. This is the fallback cadence.
        let entry = UsageEntry(date: Date(), snapshot: SnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
    }
}

@main
struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Session, weekly and model-specific plan usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    /// Snapshots older than this are marked stale, e.g. when the host app is not running.
    private static let staleAfter: TimeInterval = 20 * 60

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.limits.isEmpty {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                header(snapshot)
                ForEach(snapshot.limits.prefix(3)) { limit in
                    LimitRow(limit: limit, compact: family == .systemSmall)
                }
                Spacer(minLength: 0)
                footer(snapshot)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Usage").font(.headline)
                Text(entry.snapshot?.error ?? "Open the Claude Usage app to start fetching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func header(_ snapshot: UsageSnapshot) -> some View {
        HStack {
            Text("Claude").font(.headline)
            Spacer()
            if snapshot.error != nil || entry.date.timeIntervalSince(snapshot.fetchedAt) > Self.staleAfter {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private func footer(_ snapshot: UsageSnapshot) -> some View {
        Group {
            if let error = snapshot.error, family != .systemSmall {
                Text(error).lineLimit(1)
            } else {
                Text("Updated \(snapshot.fetchedAt, style: .relative) ago")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct LimitRow: View {
    let limit: UsageLimit
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.label)
                    .font(compact ? .caption : .subheadline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !compact, let reset = limit.resetsAt {
                    Text(reset, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(Int(limit.percent.rounded()))%")
                    .font((compact ? Font.caption : .subheadline).monospacedDigit().weight(.semibold))
            }
            ProgressView(value: min(max(limit.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(color)
        }
    }

    private var color: Color {
        switch limit.severity {
        case "critical": return .red
        case "warning": return .orange
        default: return limit.percent >= 90 ? .red : limit.percent >= 70 ? .orange : .accentColor
        }
    }
}

#Preview(as: .systemMedium) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry(date: Date(), snapshot: .placeholder)
}
