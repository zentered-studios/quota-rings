import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct QuotaRingsApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = UsageModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.snapshot?.limits ?? []))
            if let title = model.menuBarTitle {
                Text(title)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Clicking the desktop widget opens the running app. Treat that as "refresh now".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { await UsageModel.shared.refresh() }
        return false
    }
}

@MainActor
final class UsageModel: ObservableObject {
    static let shared = UsageModel()
    static let pollInterval: TimeInterval = 5 * 60
    private static let didSetUpLoginItemKey = "didSetUpLoginItem"

    @Published private(set) var snapshot: UsageSnapshot?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        snapshot = SnapshotStore.load()
        enableLoginItemOnFirstLaunch()
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // Fetch right after wake instead of waiting for the next tick.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// `session% · week%`, or nil to show the icon alone.
    var menuBarTitle: String? {
        guard let limits = snapshot?.limits, !limits.isEmpty else { return nil }
        let session = limits.first { $0.kind == .session }
        let weekly = limits.first { $0.kind == .weekly }
        let parts = [session, weekly].compactMap { $0.map { "\(Int($0.percent.rounded()))%" } }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func refresh() async {
        var next: UsageSnapshot
        do {
            let limits = try await UsageFetcher.fetch()
            next = UsageSnapshot(limits: limits, fetchedAt: Date())
        } catch {
            let status = UsageFetcher.status(for: error)
            // Keep the last good values unless the account state changed under them.
            next = snapshot ?? UsageSnapshot(limits: [], fetchedAt: Date())
            if status.clearsLimits { next.limits = [] }
            next.status = status
            next.error = error.localizedDescription
        }
        snapshot = next
        do {
            try SnapshotStore.save(next)
        } catch {
            snapshot?.status = .failed
            snapshot?.error = "Could not write \(SnapshotStore.fileURL.path): \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The widget only updates while this app runs, so start at login by default.
    /// The user can turn it off in the menu, and that choice sticks.
    private func enableLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.didSetUpLoginItemKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.didSetUpLoginItemKey)
        setLaunchAtLogin(true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Quota Rings: launch at login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct MenuContent: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        if let snapshot = model.snapshot {
            if let status = snapshot.status {
                Label(status.title, systemImage: status.symbol)
                Text(status.detail)
                if let error = snapshot.error, status == .failed {
                    Text(error)
                }
                Divider()
            }
            ForEach(snapshot.limits) { limit in
                Text("\(limit.label): \(Int(limit.percent.rounded()))%\(resetText(limit))")
            }
            if !snapshot.limits.isEmpty {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                Divider()
            }
        } else {
            Text("Loading…")
            Divider()
        }
        Button("Refresh Now") { Task { await model.refresh() } }
            .keyboardShortcut("r")
        Toggle("Open at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("Quit Quota Rings") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func resetText(_ limit: UsageLimit) -> String {
        guard let reset = limit.resetsAt else { return "" }
        return " (resets \(reset.formatted(.relative(presentation: .named))))"
    }
}
