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
        // The agent pushes reloads after each fetch. One entry per minute keeps the
        // "resets in" and "updated" labels current in between.
        let snapshot = SnapshotStore.load()
        let now = Date()
        let entries = (0..<5).map { UsageEntry(date: now.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60))))
    }
}

@main
struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Claude Usage")
        .description("Session, weekly and model-specific plan usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetContent(size: family == .systemSmall ? .small : .medium, snapshot: entry.snapshot, now: entry.date)
    }
}

#Preview(as: .systemMedium) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry(date: Date(), snapshot: .placeholder)
}
