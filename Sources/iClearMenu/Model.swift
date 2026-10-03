import AppKit
import Carbon.HIToolbox
import Foundation
import ICCore
import ICSystem
import UserNotifications

func localized(_ key: String) -> String { NSLocalizedString(key, bundle: .module, comment: "") }

/// Talks to the daemon over IPC. The menu app never signals anything itself, except
/// the emergency "thaw all" from the journal when the daemon is not running.
@MainActor
final class Model: ObservableObject {
    @Published var status: Status?
    @Published var detail: String?
    @Published var detailTitle = ""
    @Published var message: String?
    @Published var accessibility = false
    @Published var stashes: [StashRecord] = []
    @Published var batteryLine: String?
    @Published var stashName = ""
    @Published var brake: BrakeStatus?
    @Published var capacityLine: String?
    /// The one-time question after install: the brake starts in observe mode.
    @Published var brakePromptDone = UserDefaults.standard.bool(forKey: "brakePromptDone")
    private var lastBrakeEvent = Date().timeIntervalSince1970

    let paths = Paths()
    private var timer: Timer?
    private var lastEvent = Date().timeIntervalSince1970
    private var hotKeys: [HotKey] = []

    /// Inside iClear.app the daemon lives in Contents/Helpers; in a build folder, next to us.
    var daemonPath: String {
        let dir = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
        let helper = dir.deletingLastPathComponent().appendingPathComponent("Helpers/icleard").path
        return FileManager.default.fileExists(atPath: helper) ? helper : dir.appendingPathComponent("icleard").path
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        hotKeys = [HotKey(key: kVK_ANSI_T, id: 1) { [weak self] in Task { @MainActor in self?.thawAll() } }]
        let config = (try? Data(contentsOf: paths.config)).flatMap { try? Config.load(json: $0).0 }
        if config?.stash.hotkeys == true {
            hotKeys.append(HotKey(key: kVK_ANSI_S, id: 2) { [weak self] in Task { @MainActor in self?.stash("quick") } })
            hotKeys.append(HotKey(key: kVK_ANSI_P, id: 3) { [weak self] in Task { @MainActor in self?.pop("quick") } })
        }
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
        stashes = send("stashes")?.data.flatMap { try? JSONDecoder().decode([StashRecord].self, from: Data($0.utf8)) } ?? []
        if let d = send("battery")?.data, let b = try? JSONDecoder().decode(BatterySummary.self, from: Data(d.utf8)), let m = b.minutes {
            let label = localized(!b.reliable ? "battery.unreliable" : b.calibrated ? "battery.estimate" : "battery.uncalibrated")
            batteryLine = String(format: localized("battery.line"), Int(b.percent), b.watts, Int(m)) + " " + label
        } else {
            batteryLine = nil
        }
        if let d = send("capacity")?.data, let c = try? JSONDecoder().decode(CapacityReport.self, from: Data(d.utf8)) {
            capacityLine =
                c.episodes == 0
                ? localized("capacity.none")
                : String(format: localized("capacity.line"), c.episodes, c.gainMedianMB.map { String(format: "%+.0f", $0) } ?? "?")
        } else {
            capacityLine = nil
        }
        let b = IPC.send(Request("status"), path: paths.brakeSocket.path, timeout: 2)
        brake = b?.data.flatMap { try? JSONDecoder().decode(BrakeStatus.self, from: Data($0.utf8)) }
        if let e = IPC.send(Request("events", value: "\(lastBrakeEvent)"), path: paths.brakeSocket.path, timeout: 2),
            let events = e.data.flatMap({ try? JSONDecoder().decode([DaemonEvent].self, from: Data($0.utf8)) })
        {
            for ev in events { post(ev) }
            lastBrakeEvent = events.map(\.t).max() ?? lastBrakeEvent
        }
        if let e = send("events", value: "\(lastEvent)"), let data = e.data?.data(using: .utf8),
            let events = try? JSONDecoder().decode([DaemonEvent].self, from: data)
        {
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
        if let r = send(cmd, app: app, value: value) { message = r.text } else { message = localized("daemon.notRunning") }
        refresh()
    }

    /// Works with or without the daemon (safety: the emergency exit always works).
    func thawAll() {
        if let r = send("thaw", app: "all") {
            message = r.text
        } else {
            let r = Signals.recover(journal: JournalStore(url: paths.journal))
            message = String(format: localized("thawAll.offline"), r.thawed)
        }
        refresh()
    }

    func thaw(_ id: String) { run("thaw", app: id) }
    func brakeResume(_ id: String) { message = IPC.send(Request("resume", app: id), path: paths.brakeSocket.path)?.text }
    func brakeQuit(_ id: String) { message = IPC.send(Request("quit", app: id), path: paths.brakeSocket.path)?.text }
    /// Same as `iclear brake on|observe`: the config file holds the mode; the watchdog reloads it.
    func setBrake(_ mode: BrakeMode) {
        var c = (try? Data(contentsOf: paths.config)).flatMap { try? Config.load(json: $0).0 } ?? Config()
        c.brake.mode = mode
        try? Files.atomicWrite(c.encoded(), to: paths.config)
        UserDefaults.standard.set(true, forKey: "brakePromptDone")
        brakePromptDone = true
        message = mode == .on ? localized("brake.nowOn") : localized("brake.nowObserve")
    }
    func dismissUnclean() {
        try? FileManager.default.removeItem(at: paths.blackBoxUnclean)
        refresh()
    }
    func stash(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        run("stash", app: n.isEmpty ? "quick" : n, value: "{}")
        stashName = ""
    }
    func pop(_ name: String) { run("pop", app: name) }
    func neverFreeze(_ id: String) { run("deny", app: id) }
    func undo() { run("undo") }
    func setMode(_ m: Mode) { run("mode", value: m.rawValue) }
    func acceptContext() { run("context", app: "accept") }
    func dismissContext() { run("context", app: "dismiss") }
    func setProfile(_ p: String) { run("profile", value: p) }

    func show(_ cmd: String, title: String) {
        detailTitle = title
        detail = send(cmd)?.text ?? localized("daemon.notRunning")
    }

    func startDaemon() {
        message = (try? Installer(paths: paths, daemonPath: daemonPath).install()) ?? localized("daemon.installFailed")
        // The Panic Brake starts in observe mode next to the daemon.
        let brakePath = daemonPath.replacingOccurrences(of: "/icleard", with: "/icbrake")
        if FileManager.default.isExecutableFile(atPath: brakePath) {
            _ = try? Installer(paths: paths, daemonPath: brakePath, role: "brake").install()
        }
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
