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
    private static let dataSourceKey = "dataSource"

    @Published private(set) var snapshot: UsageSnapshot?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var dataSource: DataSource =
        DataSource(rawValue: UserDefaults.standard.string(forKey: UsageModel.dataSourceKey) ?? "") ?? .claudeCode
    @Published private(set) var hasClaudeAISession = SessionKeyStore.load() != nil

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// Bumped by every refresh. A fetch that finishes after a newer one started is dropped,
    /// so a slow request cannot overwrite fresher numbers or another source's result.
    private var refreshGeneration = 0

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
        refreshGeneration += 1
        let generation = refreshGeneration
        let source = dataSource
        let result: Result<[UsageLimit], Error>
        do {
            result = .success(try await source.fetch())
        } catch {
            result = .failure(error)
        }
        guard generation == refreshGeneration else { return }

        var next: UsageSnapshot
        switch result {
        case .success(let limits):
            next = UsageSnapshot(limits: limits, fetchedAt: Date())
        case .failure(let error):
            let status = source.status(for: error)
            // Keep the last good values unless the account state changed under them.
            next = snapshot ?? UsageSnapshot(limits: [], fetchedAt: Date())
            if status.clearsLimits { next.limits = [] }
            next.status = status
            next.statusDetail = source.detail(for: status, error: error)
            next.error = error.localizedDescription
        }
        hasClaudeAISession = SessionKeyStore.load() != nil
        snapshot = next
        do {
            try SnapshotStore.save(next)
        } catch {
            snapshot?.status = .failed
            snapshot?.error = "Could not write \(SnapshotStore.fileURL.path): \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setDataSource(_ source: DataSource) {
        guard source != dataSource else { return }
        dataSource = source
        UserDefaults.standard.set(source.rawValue, forKey: Self.dataSourceKey)
        // Drop any fetch still running for the previous source. The sign-in branch below
        // does not start a refresh of its own, so this cannot wait for refresh() to do it.
        refreshGeneration += 1
        // Numbers from the other source may belong to another account.
        snapshot?.limits = []
        if source == .claudeAI && SessionKeyStore.load() == nil {
            signInToClaudeAI()
        } else {
            Task { await refresh() }
        }
    }

    func signInToClaudeAI() {
        SignInWindowController.show { [weak self] in
            Task { await self?.refresh() }
        }
    }

    func signOutOfClaudeAI() {
        SessionKeyStore.delete()
        hasClaudeAISession = false
        Task { await refresh() }
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
            if let status = snapshot.status {
                Label(status.title, systemImage: status.symbol)
                if let detail = snapshot.detailText { Text(detail) }
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
        Picker("Data Source", selection: Binding(
            get: { model.dataSource },
            set: { model.setDataSource($0) }
        )) {
            ForEach(DataSource.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
        }
        if model.dataSource == .claudeAI {
            if model.hasClaudeAISession {
                Button("Sign Out of claude.ai") { model.signOutOfClaudeAI() }
            } else {
                Button("Sign In to claude.ai…") { model.signInToClaudeAI() }
            }
        }
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
