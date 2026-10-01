import AppKit
import ApplicationServices
import Foundation
import ICCore
import ICSystem

/// 7-day soak supervisor (docs/RELEASE_CRITERIA.md W1-W7), started by a LaunchAgent
/// through "iClear Lab.app". Fixtures are hidden ic-ui-probe apps with their own bundle
/// IDs, so nothing the user opens is ever routed into one. An Active, scope-locked lab
/// daemon acts only on them.
final class Soak {
    struct Day: Codable {
        var date = ""
        var awakeSeconds = 0.0
        var freezeCycles = 0, freezeFailures = 0, stashCycles = 0, stashFailures = 0, policyFreezes = 0
        var pressureEpisodes = 0, daemonRestarts = 0, fixtureRespawns = 0, leftStopped = 0, hangs = 0
        var crashReports: [String] = []
        var labCPU: [Double] = [], labRSS: [Double] = [], observeCPU: [Double] = [], observeRSS: [Double] = []
        var notes: [String] = []
    }
    struct State: Codable {
        var startedAt = Date().timeIntervalSince1970
        var days: [Day] = []
        var lastPressure = 0.0
    }

    let dir: URL
    let tools: URL
    let paths: Paths
    var state: State
    var daemon: Process?
    var probes: [GUIFixture] = []
    var stashUntil: Double?
    var stashName = ""
    var lastTick = Date().timeIntervalSince1970
    var cpuMark: [Int32: (cpu: UInt64, t: Double)] = [:]
    var running = true

    init(dir: URL, tools: URL) {
        self.dir = dir
        self.tools = tools
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths = Paths(environment: ["ICLEAR_HOME": dir.appendingPathComponent("lab-home").path, "ICLEAR_INSTANCE": "soak"])
        state = (try? Files.readJSON(State.self, from: dir.appendingPathComponent("state.json"))) ?? State()
    }

    func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        Files.appendLine(Data("\(f.string(from: Date())) \(s)\n".utf8), to: dir.appendingPathComponent("soak.log"), maxBytes: 20 << 20)
    }

    var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// The current day's record (a new one when the date changes; the old one is reported).
    var day: Day {
        get { state.days.last ?? Day() }
        set {
            if state.days.isEmpty { state.days.append(newValue) } else { state.days[state.days.count - 1] = newValue }
        }
    }

    func save() { try? Files.writeJSON(state, to: dir.appendingPathComponent("state.json"), pretty: true) }

    // MARK: fixtures and the lab daemon

    func registry() -> [ProcessIdentity] { probes.compactMap(\.identity) }

    func ensureFixtures() {
        probes.removeAll { p in
            guard Proc.startTime(p.pid) == nil else { return false }
            day.fixtureRespawns += 1
            log("fixture \(p.id) exited; respawning")
            return true
        }
        let frames = ["40,60,320,200", "380,60,320,200", "720,60,320,200"]
        while probes.count < 3 {
            guard
                let f = try? GUIFixture(
                    probe: tools.appendingPathComponent("ic-ui-probe").path, dir: dir.appendingPathComponent("fixtures"),
                    name: "SoakProbe\(probes.count)", frame: frames[probes.count])
            else { break }
            f.app.hide()
            fixturePIDs.insert(f.pid)
            probes.append(f)
        }
        try? JSONEncoder().encode(registry()).write(to: paths.labRegistry)
    }

    func ensureDaemon() {
        if let d = daemon, d.isRunning { return }
        if daemon != nil {
            day.daemonRestarts += 1
            log("lab daemon exited (status \(daemon!.terminationStatus)); restarting")
        }
        try? paths.ensure()
        var cfg = Config()
        cfg.mode = .active
        cfg.idleMinutes = 5
        cfg.minFrozenMinutes = 2
        cfg.cooldownMinutes = 2
        cfg.thawAfterNormalMinutes = 5
        cfg.callMode.enabled = true
        cfg.antiBeachball.forensics = false  // it would query the user's frontmost app
        try? Files.writeJSON(cfg, to: paths.config, pretty: true)
        let d = Process()
        d.executableURL = tools.appendingPathComponent("icleard")
        d.environment = ProcessInfo.processInfo.environment.merging(
            ["ICLEAR_HOME": paths.home.path, "ICLEAR_INSTANCE": "soak", "ICLEAR_LAB": "1"]) { _, n in n }
        d.standardError = FileHandle.nullDevice
        try? d.run()
        fixturePIDs.insert(d.processIdentifier)
        daemon = d
        for _ in 0..<100 where IPC.send(Request("ping"), path: paths.socket.path, timeout: 1)?.ok != true { usleep(100_000) }
    }

    func ask(_ cmd: String, app: String? = nil, value: String? = nil) -> Response? {
        IPC.send(Request(cmd, app: app, value: value), path: paths.socket.path, timeout: 60)
    }

    func stopped(_ f: GUIFixture) -> Bool { Proc.bsdInfo(f.pid)?.pbi_status == UInt32(SSTOP) }

    // MARK: work

    /// One freeze/thaw cycle on one fixture through the daemon (`iclear freeze` / `thaw`).
    func freezeCycle() {
        guard stashUntil == nil, let f = probes.randomElement() else { return }
        let r = ask("freeze", app: f.id)
        let frozen = r?.ok == true && stopped(f)
        usleep(UInt32.random(in: 2_000_000...15_000_000))
        _ = ask("thaw", app: f.id)
        usleep(300_000)
        if frozen && !stopped(f) {
            day.freezeCycles += 1
        } else {
            day.freezeFailures += 1
            log("freeze cycle on \(f.id): \(r?.text.split(separator: "\n").first ?? "no answer"); stopped after thaw: \(stopped(f))")
        }
    }

    func stashStep(now: Double) {
        if let until = stashUntil {
            guard now >= until else { return }
            let r = ask("pop", app: stashName)
            usleep(500_000)
            if r?.ok == true && probes.allSatisfy({ !stopped($0) }) {
                day.stashCycles += 1
            } else {
                day.stashFailures += 1
                log("pop \(stashName): \(r?.text ?? "no answer")")
            }
            stashUntil = nil
            return
        }
        stashName = "soak\(Int(now))"
        // Fixtures are hidden, so the stash only pauses them and pop changes nothing on screen.
        let r = ask("stash", app: stashName, value: "{}")
        if r?.ok == true && probes.allSatisfy({ stopped($0) }) {
            stashUntil = now + Double.random(in: 60...300)
        } else {
            day.stashFailures += 1
            log("stash: \(r?.text.split(separator: "\n").first ?? "no answer")")
            _ = ask("pop", app: stashName)
        }
    }

    /// Bounded pressure while the user is away: idle ≥ 10 min, on AC, pressure normal,
    /// ≤ 30% of RAM, at most once every 2 h; stops at warning, on critical, or when swap
    /// grows by 1 GB.
    func pressureStep(now: Double) {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle >= 600, now - state.lastPressure >= 7200, SystemSampler.pressure() == .normal,
            SmartBattery().read(now: now).map({ $0.onAC }) ?? true, stashUntil == nil
        else { return }
        state.lastPressure = now
        let p = Pressure(hogPath: tools.appendingPathComponent("ic-hog").path)
        let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
        let before = ActionLog.read(paths: paths, last: 100_000).filter { $0.action.kind == .freeze }.count
        let why = p.ramp(
            capMB: ram * 0.3,  // the soak runs on a Mac in daily use: 30%, not the lab's 45%
            stopAt: {
                SystemSampler.pressure() >= .warning
                    || CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 5
            }, tick: {})
        for _ in 0..<12 {
            sleep(5)
            if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 5 { break }
        }
        p.release()
        let after = ActionLog.read(paths: paths, last: 100_000).filter { $0.action.kind == .freeze }.count
        day.pressureEpisodes += 1
        day.policyFreezes += after - before
        log("pressure episode: \(why), peak \(p.peak.name); daemon freezes \(after - before)")
    }

    /// Invariants: nothing stopped outside the daemon's journal, running fixtures answer.
    func checks() {
        let journaled = Set(JournalStore(url: paths.journal).read().entries.map(\.pid))
        for f in probes {
            if stopped(f) && !journaled.contains(f.pid) {
                day.leftStopped += 1
                log("VIOLATION: \(f.id) stopped without a journal entry; resuming")
                if let id = f.identity { _ = Signals.send(SIGCONT, to: id) }
            }
            if !stopped(f), AXIsProcessTrusted() {
                let el = AXUIElementCreateApplication(f.pid)
                AXUIElementSetMessagingTimeout(el, 5)
                var v: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) != .success && !stopped(f) {
                    day.hangs += 1
                    log("hang: \(f.id) did not answer within 5 s")
                }
            }
        }
    }

    /// CPU % of one core since the last sample, and resident MB.
    func overhead(_ pid: Int32, now: Double) -> (Double, Double)? {
        guard let i = Proc.info(pid) else { return nil }
        defer { cpuMark[pid] = (i.cpuNanos, now) }
        guard let m = cpuMark[pid], now > m.t else { return nil }
        return (Double(i.cpuNanos &- m.cpu) / 1e9 / (now - m.t) * 100, i.residentMB)
    }

    func observePID() -> Int32? {
        let path = tools.appendingPathComponent("icleard").path
        return Proc.table().values.first { $0.ppid == 1 && $0.path == path }?.pid
    }

    func report(_ d: Day) {
        func p95(_ x: [Double]) -> String { x.isEmpty ? "n/a" : String(format: "%.2f", percentileOf(x, 0.95)) }
        func avg(_ x: [Double]) -> String { x.isEmpty ? "n/a" : String(format: "%.3f", x.reduce(0, +) / Double(x.count)) }
        let observe =
            IPC.send(
                Request("stats", value: "1"),
                path: Paths(environment: ["ICLEAR_INSTANCE": "observe"]).socket.path, timeout: 10)?.text ?? "observe instance not answering"
        let md = """
            # Soak report \(d.date)

            Soak started \(Date(timeIntervalSince1970: state.startedAt)). Awake time this day: \(String(format: "%.1f", d.awakeSeconds / 3600)) h.

            | Measure | Value |
            |---|---|
            | Freeze/thaw cycles OK / failed | \(d.freezeCycles) / \(d.freezeFailures) |
            | Stash/pop cycles OK / failed | \(d.stashCycles) / \(d.stashFailures) |
            | Pressure episodes / daemon freezes during them | \(d.pressureEpisodes) / \(d.policyFreezes) |
            | Processes found stopped without a journal entry | \(d.leftStopped) |
            | Fixture hangs (no answer in 5 s) | \(AXIsProcessTrusted() ? "\(d.hangs)" : "not measured (no Accessibility)") |
            | Lab daemon restarts / fixture respawns | \(d.daemonRestarts) / \(d.fixtureRespawns) |
            | New crash reports from fixtures | \(d.crashReports.count) \(d.crashReports.joined(separator: ", ")) |
            | Lab daemon CPU (mean of 1-min samples, % of one core) / p95 RSS MB | \(avg(d.labCPU)) / \(p95(d.labRSS)) |
            | Observe daemon CPU / p95 RSS MB | \(avg(d.observeCPU)) / \(p95(d.observeRSS)) |

            ## Observe instance (real apps, never acts), last 24 h

            ```
            \(observe)
            ```
            \(d.notes.isEmpty ? "" : "\nNotes:\n" + d.notes.map { "- " + $0 }.joined(separator: "\n"))
            """
        try? Data(md.utf8).write(to: dir.appendingPathComponent("report-\(d.date).md"))
    }

    func tick() {
        let now = Date().timeIntervalSince1970
        if day.date != today {
            if !day.date.isEmpty { report(day) }
            state.days.append(Day(date: today))
        }
        // A long gap means the Mac slept; only awake time counts.
        let gap = now - lastTick
        if gap < 180 { day.awakeSeconds += gap }
        lastTick = now
        ensureDaemon()
        ensureFixtures()
        if let d = daemon, let (c, r) = overhead(d.processIdentifier, now: now) {
            day.labCPU.append(c)
            day.labRSS.append(r)
        }
        if let pid = observePID(), let (c, r) = overhead(pid, now: now) {
            day.observeCPU.append(c)
            day.observeRSS.append(r)
        }
        stashStep(now: now)
        pressureStep(now: now)
        checks()
        let since = Date(timeIntervalSince1970: now - gap - 1)
        for c in newCrashReports(names: ["ic-ui-probe", "SoakProbe", "icleard"], since: since) where !day.crashReports.contains(c) {
            day.crashReports.append(c)
            log("crash report: \(c)")
        }
        report(day)
        save()
    }

    func run() {
        log("soak supervisor started; Accessibility \(AXIsProcessTrusted())")
        if state.days.isEmpty { log("soak start recorded: \(Date(timeIntervalSince1970: state.startedAt))") }
        var nextTick = 0.0
        while running {
            let now = Date().timeIntervalSince1970
            if now >= nextTick {
                tick()
                nextTick = now + 60
            }
            freezeCycle()
            sleep(UInt32.random(in: 5...20))
        }
    }

    func stop() {
        running = false
        _ = ask("thaw", app: "all")
        if let d = daemon, d.isRunning {
            d.terminate()
            d.waitUntilExit()
        }
        for p in probes { p.kill() }
        report(day)
        save()
        log("soak supervisor stopped")
    }
}
