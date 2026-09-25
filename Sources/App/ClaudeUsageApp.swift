import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Text(model.menuBarTitle)
        }
    }
}

@MainActor
final class UsageModel: ObservableObject {
    static let pollInterval: TimeInterval = 5 * 60

    @Published private(set) var snapshot: UsageSnapshot?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var timer: Timer?

    init() {
        snapshot = SnapshotStore.load()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    var menuBarTitle: String {
        guard let limits = snapshot?.limits, !limits.isEmpty else { return "Claude –" }
        let session = limits.first { $0.kind == .session }
        let weekly = limits.first { $0.kind == .weekly }
        let parts = [session, weekly].compactMap { $0.map { "\(Int($0.percent.rounded()))%" } }
        return parts.isEmpty ? "Claude" : parts.joined(separator: " · ")
    }

    func refresh() async {
        var next: UsageSnapshot
        do {
            let limits = try await UsageFetcher.fetch()
            next = UsageSnapshot(limits: limits, fetchedAt: Date(), error: nil)
        } catch {
            // Keep the last good values and report the failure next to them.
            next = snapshot ?? UsageSnapshot(limits: [], fetchedAt: Date(), error: nil)
            next.error = error.localizedDescription
        }
        snapshot = next
        do {
            try SnapshotStore.save(next)
        } catch {
            snapshot?.error = "Could not write \(SnapshotStore.fileURL.path): \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            snapshot?.error = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct MenuContent: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        if let snapshot = model.snapshot {
            ForEach(snapshot.limits) { limit in
                Text("\(limit.label): \(Int(limit.percent.rounded()))%\(resetText(limit))")
            }
            if let error = snapshot.error {
                Divider()
                Text(error)
            }
            Divider()
            Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("Loading…")
        }
        Divider()
        Button("Refresh Now") { Task { await model.refresh() } }
            .keyboardShortcut("r")
        Toggle("Open at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func resetText(_ limit: UsageLimit) -> String {
        guard let reset = limit.resetsAt else { return "" }
        return " (resets \(reset.formatted(.relative(presentation: .named))))"
    }
}
