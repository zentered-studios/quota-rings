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
            Text(UsageSnapshot.menuBarTitle(for: model.snapshot))
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
    /// Bumped by every refresh. A fetch that finishes after a newer one started is dropped,
    /// so a slow request cannot overwrite fresher numbers.
    private var refreshGeneration = 0

    private init() {
        snapshot = SnapshotStore.load()
        Self.removeClaudeAISession()
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

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let result: Result<[UsageLimit], Error>
        do {
            result = .success(try await UsageFetcher.fetch())
        } catch {
            result = .failure(error)
        }
        let codex = await Task.detached { CodexReader.read() }.value
        guard generation == refreshGeneration else { return }

        var next: UsageSnapshot
        switch result {
        case .success(let limits):
            next = UsageSnapshot(limits: limits, fetchedAt: Date())
        case .failure(let error):
            let status = UsageFetcher.status(for: error)
            // Keep the last good values unless the account state changed under them.
            next = snapshot ?? UsageSnapshot(limits: [], fetchedAt: Date())
            if status.clearsLimits { next.limits = [] }
            next.status = status
            next.error = error.localizedDescription
        }
        next.codex = codex
        snapshot = next
        do {
            try SnapshotStore.save(next)
        } catch {
            snapshot?.status = .failed
            snapshot?.error = "Could not write \(SnapshotStore.fileURL.path): \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Earlier builds could sign in to claude.ai and kept its session key in the Keychain.
    /// That source is gone, so delete any key and setting it left behind.
    private static func removeClaudeAISession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.zentered.quotarings.claude-ai"]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "dataSource")
    }

    /// The widget only updates while this app runs, so offer to start at login once.
    /// The answer sticks; the menu toggle changes it later.
    private func enableLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.didSetUpLoginItemKey) else { return }
        guard SMAppService.mainApp.status != .enabled else {
            UserDefaults.standard.set(true, forKey: Self.didSetUpLoginItemKey)
            return
        }
        // Ask after launch finishes, so the alert has an app to belong to.
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Open Quota Rings at login?"
            alert.informativeText = "The widget only updates while Quota Rings is running. You can change this later in the menu bar menu."
            alert.addButton(withTitle: "Open at Login")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            // Only a real answer counts, so quitting with the alert open asks again next launch.
            UserDefaults.standard.set(true, forKey: Self.didSetUpLoginItemKey)
            if response == .alertFirstButtonReturn {
                self?.setLaunchAtLogin(true)
            }
        }
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
            Section("Claude") {
                if let status = snapshot.status {
                    Label(status.title, systemImage: status.symbol)
                    Text(status.detail)
                    if let error = snapshot.error, status == .failed {
                        Text(error)
                    }
                }
                ForEach(snapshot.limits) { limit in
                    Text(menuText(limit))
                }
            }
            if let codex = snapshot.codex, !codex.isEmpty {
                Section("Codex") {
                    ForEach(codex) { limit in
                        Text(menuText(limit))
                    }
                }
            }
            if !snapshot.limits.isEmpty || snapshot.codex?.isEmpty == false {
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

    /// "Week: 69% (resets in 2 days)".
    private func menuText(_ limit: UsageLimit) -> String {
        let percent = "\(limit.label): \(Int(limit.percent.rounded()))%"
        guard let reset = limit.resetsAt else { return percent }
        return "\(percent) (resets \(reset.formatted(.relative(presentation: .named))))"
    }
}
