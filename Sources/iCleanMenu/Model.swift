import AppKit
import Foundation
import ICCore
import ICSystem
import UserNotifications

func L(_ key: String) -> String { NSLocalizedString(key, bundle: .module, comment: "") }

/// Talks to the daemon over IPC. The menu app never signals anything itself, except
/// the emergency "thaw all" from the journal when the daemon is not running.
@MainActor
final class Model: ObservableObject {
    @Published var status: Status?
    @Published var detail: String?
    @Published var detailTitle = ""
    @Published var message: String?
    @Published var accessibility = false

    let paths = Paths()
    private var timer: Timer?
    private var lastEvent = Date().timeIntervalSince1970
    private var hotKey: HotKey?

    /// Inside iClean.app the daemon lives in Contents/Helpers; in a build folder, next to us.
    var daemonPath: String {
        let dir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
        let helper = dir.deletingLastPathComponent().appendingPathComponent("Helpers/icleand").path
        return FileManager.default.fileExists(atPath: helper) ? helper : dir.appendingPathComponent("icleand").path
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        hotKey = HotKey { [weak self] in Task { @MainActor in self?.thawAll() } }
        // Notifications need a real app bundle.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    private func send(_ cmd: String, app: String? = nil, value: String? = nil, json: Bool = false) -> Response? {
        IPC.send(Request(cmd, app: app, value: value, json: json), path: paths.socket.path, timeout: 5)
    }

    func refresh() {
        accessibility = Permissions.status().accessibility
        guard let r = send("status", json: true), let d = r.data?.data(using: .utf8) else {
            status = nil
            return
        }
        status = try? JSONDecoder().decode(Status.self, from: d)
        if let e = send("events", value: "\(lastEvent)"), let data = e.data?.data(using: .utf8),
           let events = try? JSONDecoder().decode([DaemonEvent].self, from: data) {
            for ev in events { post(ev) }
            lastEvent = events.map(\.t).max() ?? lastEvent
        }
    }

    private func post(_ e: DaemonEvent) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = e.title
        c.body = e.body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func run(_ cmd: String, app: String? = nil, value: String? = nil) {
        if let r = send(cmd, app: app, value: value) { message = r.text } else { message = L("daemon.notRunning") }
        refresh()
    }

    /// Works with or without the daemon (safety: the emergency exit always works).
    func thawAll() {
        if let r = send("thaw", app: "all") {
            message = r.text
        } else {
            let r = Signals.recover(journal: JournalStore(url: paths.journal))
            message = String(format: L("thawAll.offline"), r.thawed)
        }
        refresh()
    }

    func thaw(_ id: String) { run("thaw", app: id) }
    func neverFreeze(_ id: String) { run("deny", app: id) }
    func undo() { run("undo") }
    func setMode(_ m: Mode) { run("mode", value: m.rawValue) }
    func setProfile(_ p: String) { run("profile", value: p) }

    func show(_ cmd: String, title: String) {
        detailTitle = title
        detail = send(cmd)?.text ?? L("daemon.notRunning")
    }

    func startDaemon() {
        message = (try? Installer(paths: paths, daemonPath: daemonPath).install()) ?? L("daemon.installFailed")
        refresh()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    var icon: String {
        guard let s = status else { return "questionmark.circle" }
        if s.frozen.contains(where: { !$0.dryRun }) { return "snowflake" }
        switch s.health.band {
        case .good: return "checkmark.circle"
        case .fair: return "exclamationmark.circle"
        case .poor: return "exclamationmark.triangle"
        }
    }
}
