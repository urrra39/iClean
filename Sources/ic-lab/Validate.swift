import AppKit
import ApplicationServices
import Foundation
import ICCore
import ICSystem

/// Validation phases for docs/RELEASE_CRITERIA.md. Every phase writes a JSON result and
/// a markdown section into the output directory.
final class Lab {
    let out: URL
    let started = Date()
    private let logURL: URL
    var fixtures: [AppFixture] = []
    var probes: [GUIFixture] = []
    let journal: JournalStore
    var markdown: [String] = []
    /// Lab processes that are not app fixtures (simulator apps).
    var extra: [ProcessIdentity] = []
    /// Guards `fixtures`, `probes` and `extra` against the registry timers.
    let regLock = NSLock()
    var registryTimers: [String: DispatchSourceTimer] = [:]
    /// Lab daemons started by this run; stopped on every exit path (they resume what they paused).
    var daemons: [Process] = []
    /// Every fixture this run started, even while a phase works on a subset.
    var everStarted: [AppFixture] = []
    let condLock = NSLock()
    var conditions: [String: Int] = [:]
    var forecast = ForecastState()
    var forecastLog: [String] = []
    var batteryTrace: [[Double]] = []

    init(out: URL) {
        self.out = out
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        logURL = out.appendingPathComponent("run.log")
        // One journal per lab process: two phases running at once never share one.
        journal = JournalStore(url: out.appendingPathComponent("lab-journal-\(getpid()).json"))
    }

    func log(_ s: String) {
        let line = String(format: "[%6.0fs] ", Date().timeIntervalSince(started)) + s
        print(line)
        Files.appendLine(Data((line + "\n").utf8), to: logURL, maxBytes: 50 << 20)
    }

    /// Writes a phase's result with the power source and thermal state seen while it ran.
    func save<T: Encodable>(_ name: String, _ v: T, _ md: String) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(v).write(to: out.appendingPathComponent("\(name).json"))
        condLock.lock()
        let cond = conditions
        conditions = [:]
        condLock.unlock()
        try? e.encode(cond).write(to: out.appendingPathComponent("\(name)-conditions.json"))
        let text = cond.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        Files.appendLine(
            Data((md + "\n\nConditions (samples during the run): \(text.isEmpty ? "not sampled" : text).\n\n").utf8),
            to: out.appendingPathComponent("summary.md"), maxBytes: 10 << 20)
        log("saved \(name) (\(text))")
    }

    static var thermalName: String {
        ["nominal", "fair", "serious", "critical"][min(3, ProcessInfo.processInfo.thermalState.rawValue)]
    }

    /// Power source and thermal state, sampled once per cycle, pair or minute.
    func noteConditions() {
        let power =
            SmartBattery().read(now: 0).map {
                $0.onAC ? "AC" : String(format: "battery %.0f%%", ($0.percent / 10).rounded(.down) * 10) + "+"
            } ?? "AC (no battery)"
        condLock.lock()
        conditions["power \(power), thermal \(Lab.thermalName)", default: 0] += 1
        condLock.unlock()
    }

    /// Everything the lab registered: app fixture trees, probe fixtures and simulator apps.
    func registered() -> Set<ProcessIdentity> {
        regLock.lock()
        let (f, p, e) = (fixtures, probes, extra)
        regLock.unlock()
        return Set(f.flatMap { $0.tree() } + p.compactMap(\.identity) + e)
    }

    func lockScope() { ScopeLock.set(registered()) }

    /// A short home for a lab daemon: a Unix socket path must stay under 104 bytes.
    func labHome(_ name: String) -> URL { out.deletingLastPathComponent().appendingPathComponent("h/\(name)") }

    func writeRegistry(_ url: URL) { try? JSONEncoder().encode(Array(registered())).write(to: url) }

    func sampleBattery() {
        if let r = SmartBattery().read(now: Date().timeIntervalSince1970), !r.onAC {
            batteryTrace.append([r.time, r.remainingWh, r.dischargeW])
        }
    }

    func cleanup() {
        regLock.lock()
        let ds = daemons
        regLock.unlock()
        for d in ds where d.isRunning {
            d.terminate()
            d.waitUntilExit()
        }
        // Scope first: recovery must not reach anything the lab did not start.
        lockScope()
        _ = Signals.recover(journal: journal)
        regLock.lock()
        let all = everStarted + fixtures.filter { f in !everStarted.contains { $0 === f } }
        regLock.unlock()
        for f in all { f.kill() }
        GUIFixture.killAll()
        SpawnedHog.killAll()
        ScopeLock.set(nil)
    }

    /// Heavy phases wait (with nothing paused) while the Mac is unplugged below 15%, so it
    /// does not go to sleep part-way through a run; they continue at 20% or on power.
    @discardableResult
    func powerGate() -> Double {
        noteConditions()
        guard let r = SmartBattery().read(now: 0), !r.onAC, r.percent < 15 else { return 0 }
        let t = Date()
        log(String(format: "battery %.0f%% unplugged: waiting for power", r.percent))
        while let r = SmartBattery().read(now: 0), !r.onAC, r.percent < 20 { sleep(30) }
        log("continuing")
        return Date().timeIntervalSince(t)
    }

    /// The fixture's app has no other running instance (LaunchServices would pick by bundle).
    static func onlyInstance(_ f: AppFixture) -> Bool {
        f.app.bundleIdentifier.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0).count == 1 } ?? false
    }

    /// Makes this exact fixture process frontmost (Accessibility), or through LaunchServices
    /// when it is the only instance of its app.
    static func bringToFront(_ f: AppFixture) {
        if AXIsProcessTrusted() {
            let el = AXUIElementCreateApplication(f.pid)
            AXUIElementSetMessagingTimeout(el, 2)
            AXUIElementSetAttributeValue(el, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        } else if onlyInstance(f), let url = f.app.bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.createsNewApplicationInstance = false
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 5)
        }
        usleep(700_000)
    }

    /// Stash options naming every fixture, so the planner's soft risks (which need
    /// `--include`) do not keep one back; hard blocks still apply.
    var includeAll: String {
        let o = StashOptions(include: fixtures.compactMap { $0.app.bundleIdentifier }, includeHeavy: true)
        return String(decoding: (try? JSONEncoder().encode(o)) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// Log-uniform hold between 0.2 and 20 s (median about 2 s).
    static func randomHold() -> Double { exp(Double.random(in: Foundation.log(0.2)...Foundation.log(20))) }
}

/// Bounded induced pressure: incompressible 256 MB allocations up to a cap (at most 45%
/// of RAM, below the 50% limit the lab was given). A guard releases everything at once on
/// critical pressure or when swap grows by more than 1 GB, during the ramp and the hold.
final class Pressure {
    static let swapLimitMB = 1024.0
    let hogPath: String
    private let lock = NSLock()
    private var hogs: [SpawnedHog] = []
    private var timer: DispatchSourceTimer?
    let swap0 = SystemSampler.sample().swapUsedMB
    private(set) var stopReason: String?
    private(set) var peak: PressureLevel = .normal
    init(hogPath: String) { self.hogPath = hogPath }

    var heldMB: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(hogs.count * 256)
    }

    func ramp(capMB: Double, stopAt: () -> Bool, tick: () -> Void) -> String {
        let cap = min(capMB, Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576 * 0.45)
        startGuard()
        while heldMB + 256 <= cap {
            if let r = stopReason { return r }
            if stopAt() { return "target reached" }
            guard let h = try? SpawnedHog(path: hogPath, args: ["--mb", "256", "--data", "random"]), h.waitReady(timeout: 60) else { break }
            lock.lock()
            hogs.append(h)
            lock.unlock()
            tick()
        }
        return stopReason ?? "cap reached"
    }

    private func startGuard() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let level = SystemSampler.pressure()
            if level > self.peak { self.peak = level }
            let swap = SystemSampler.sample().swapUsedMB - self.swap0
            if level == .critical || swap > Pressure.swapLimitMB {
                self.stopReason = level == .critical ? "critical pressure: released" : "swap grew \(Int(swap)) MB: released"
                self.release()
            }
        }
        t.resume()
        timer = t
    }

    func release() {
        lock.lock()
        let hs = hogs
        hogs = []
        lock.unlock()
        for h in hs { h.kill() }
        timer?.cancel()
        timer = nil
    }
}

struct CycleStats: Codable {
    var fixture: String
    var kind: String
    var cycles = 0
    var pressureCycles = 0
    var freezeFailures = 0
    var hangs = 0
    var stuck = 0
    var docChanges = 0
    var latencyMs: [Double] = []
    var pressureLatencyMs: [Double] = []
    var crashReports: [String] = []
    var responsivenessMeasured = false
}

extension Lab {
    /// One freeze/thaw cycle on a fixture through the journaled path.
    func cycle(_ f: AppFixture, hold: Double, stats: inout CycleStats, pressure: Bool) {
        // The scope must include exactly the tree about to be frozen (Chrome starts helpers
        // all the time; one started between two tree reads would be refused).
        let ids = f.tree()
        ScopeLock.set(registered().union(ids))
        guard f.alive, Signals.freezeTree(ids, appID: f.name, at: Date().timeIntervalSince1970, journal: journal).ok else {
            stats.freezeFailures += 1
            return
        }
        usleep(UInt32(hold * 1_000_000))
        let t = uptimeNanos()
        Signals.thawTree(ids, journal: journal)
        if AXIsProcessTrusted() {
            stats.responsivenessMeasured = true
            if f.axPing(timeout: 5) != nil {
                let ms = Double(uptimeNanos() - t) / 1e6
                if pressure { stats.pressureLatencyMs.append(ms) } else { stats.latencyMs.append(ms) }
            } else {
                stats.hangs += 1
                log("HANG: \(f.name) did not answer within 5 s after resume")
            }
        }
        if ids.contains(where: { Proc.startTime($0.pid) == $0.startTime && Proc.bsdInfo($0.pid)?.pbi_status == UInt32(SSTOP) }) {
            stats.stuck += 1
            log("STUCK: \(f.name) still has stopped processes after thaw")
            for id in ids { _ = Signals.send(SIGCONT, to: id) }
        }
        if !f.docsIntact() {
            stats.docChanges += 1
            log("DATA: a document of \(f.name) changed")
        }
        if pressure { stats.pressureCycles += 1 }
        stats.cycles += 1
    }

    /// Soak (C1, C3, C4, C5, C6): concurrent cycles per fixture, then the same under induced pressure.
    func soak(normal: Int, underPressure: Int, hogPath: String) {
        let since = Date()
        var results = fixtures.map { CycleStats(fixture: $0.name, kind: $0.kind) }
        let lock = NSLock()
        func run(_ n: Int, pressure: Pressure?) {
            DispatchQueue.concurrentPerform(iterations: fixtures.count) { i in
                var s = CycleStats(fixture: fixtures[i].name, kind: fixtures[i].kind)
                for k in 0..<n {
                    powerGate()
                    cycle(fixtures[i], hold: Lab.randomHold(), stats: &s, pressure: (pressure?.heldMB ?? 0) > 0)
                    usleep(UInt32.random(in: 200_000...1_000_000))
                    if k % 25 == 0 { log("\(fixtures[i].name): \(k)/\(n) \(pressure != nil ? "with induced pressure" : "")") }
                }
                lock.lock()
                results[i].cycles += s.cycles
                results[i].pressureCycles += s.pressureCycles
                results[i].freezeFailures += s.freezeFailures
                results[i].hangs += s.hangs
                results[i].stuck += s.stuck
                results[i].docChanges += s.docChanges
                results[i].latencyMs += s.latencyMs
                results[i].pressureLatencyMs += s.pressureLatencyMs
                results[i].responsivenessMeasured = results[i].responsivenessMeasured || s.responsivenessMeasured
                lock.unlock()
            }
        }
        log("soak: \(normal) cycles per fixture without pressure")
        run(normal, pressure: nil)
        sampleBattery()
        log("soak: inducing pressure, then \(underPressure) cycles per fixture")
        let p = Pressure(hogPath: hogPath)
        let stop = p.ramp(capMB: .infinity, stopAt: { SystemSampler.pressure() >= .warning }, tick: { self.forecastTick() })
        let induced = p.heldMB
        log("pressure ramp stopped: \(stop), \(Int(induced)) MB induced, level \(SystemSampler.pressure().name)")
        run(underPressure, pressure: p)
        let peak = p.peak
        p.release()
        for i in results.indices {
            results[i].crashReports = newCrashReports(
                names: [fixtures[i].name, fixtures[i].app.localizedName ?? fixtures[i].name], since: since)
        }
        var md = [
            "## Soak: freeze/thaw on real apps", "",
            "| Fixture | Type | Cycles | Under pressure | Freeze failures | Hangs (no answer in 5 s) | Left stopped | Document changes | New crash reports | Thaw-to-responsive, no induced pressure | Under induced pressure |",
            "|---|---|---|---|---|---|---|---|---|---|---|",
        ]
        for r in results {
            md.append(
                "| \(r.fixture) | \(r.kind) | \(r.cycles) | \(r.pressureCycles) | \(r.freezeFailures) | \(r.responsivenessMeasured ? "\(r.hangs)" : "not measured") | \(r.stuck) | \(r.docChanges) | \(r.crashReports.count) | \(r.responsivenessMeasured ? dist(r.latencyMs) : "not measured (no Accessibility)") | \(r.responsivenessMeasured ? dist(r.pressureLatencyMs) : "not measured") |"
            )
        }
        md.append("")
        md.append(
            "Induced pressure: \(Int(induced)) MB of incompressible memory (\(stop); \(p.stopReason ?? "held to the end")); highest pressure level \(peak.name). Freeze holds log-uniform 0.2-20 s. Forecast at the end of the ramp: \(forecastLog.last ?? "no samples")."
        )
        save("soak", results, md.joined(separator: "\n"))
    }

    func forecastTick() {
        let s = SystemSampler.sample()
        var settings = Config.ForecastSettings()
        settings.enabled = true
        let (f, raised) = Forecaster.update(&forecast, sample: s, settings: settings)
        forecastLog.append(
            "\(Int(s.time)) avail \(s.availablePercent)% level \(s.pressure.name) eta-warning \(f.etaWarning.map { String(format: "%.1f min", $0) } ?? "none")\(raised ? " ALARM" : "")"
        )
    }

    /// Reclaim (§8.4 item 3): resident memory of frozen real apps before, during and after
    /// bounded pressure, one episode per run.
    func reclaim(runs: Int, hogPath: String) {
        struct Row: Codable {
            var fixture: String
            var before: [Double]
            var during: [Double]
            var after: [Double]
        }
        var rows = fixtures.map { Row(fixture: $0.name, before: [], during: [], after: []) }
        func resident(_ f: AppFixture) -> Double { f.tree().compactMap { Proc.info($0.pid)?.residentMB }.reduce(0, +) }
        let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
        for run in 0..<runs {
            powerGate()
            lockScope()
            let before = fixtures.map(resident)
            let trees = fixtures.map { $0.tree() }
            for (f, ids) in zip(fixtures, trees) { _ = Signals.freezeTree(ids, appID: f.name, at: 0, journal: journal) }
            let p = Pressure(hogPath: hogPath)
            let stop = p.ramp(
                capMB: ram,
                stopAt: {
                    zip(self.fixtures, before).allSatisfy { resident($0.0) <= $0.1 * 0.5 }
                }, tick: { self.forecastTick() })
            sleep(5)
            let during = fixtures.map(resident)
            p.release()
            for ids in trees { Signals.thawTree(ids, journal: journal) }
            sleep(10)
            let after = fixtures.map(resident)
            for i in rows.indices {
                rows[i].before.append(before[i])
                rows[i].during.append(during[i])
                rows[i].after.append(after[i])
            }
            log(
                "reclaim run \(run + 1)/\(runs): \(stop), \(Int(p.heldMB)) MB held, peak \(p.peak.name); "
                    + zip(fixtures, zip(before, during)).map { String(format: "%@ %.0f->%.0f MB", $0.0.name, $0.1.0, $0.1.1) }.joined(
                        separator: ", "))
            sampleBattery()
        }
        var md = [
            "## Reclaim on real apps (bounded induced pressure, \(runs) runs)", "",
            "| Fixture | Resident before (median MB) | While frozen under pressure | 10 s after thaw | Median reduction while frozen |",
            "|---|---|---|---|---|",
        ]
        for r in rows {
            let red = zip(r.before, r.during).map { $0.0 > 0 ? 1 - $0.1 / $0.0 : 0 }
            md.append(
                String(
                    format: "| %@ | %.0f | %.0f | %.0f | %.0f%% |", r.fixture, percentileOf(r.before, 0.5), percentileOf(r.during, 0.5),
                    percentileOf(r.after, 0.5), percentileOf(red, 0.5) * 100))
        }
        save("reclaim", rows, md.joined(separator: "\n"))
    }

    // MARK: isolated lab daemon

    func startDaemon(_ paths: Paths, tools: URL, env extra: [String: String] = [:]) -> Process? {
        try? paths.ensure()
        writeRegistry(paths.labRegistry)
        // Apps such as Chrome start helper processes all the time; each is registered within a second.
        regLock.lock()
        if registryTimers[paths.labRegistry.path] == nil {
            let t = DispatchSource.makeTimerSource(queue: .global())
            t.schedule(deadline: .now() + 1, repeating: 1)
            t.setEventHandler { [weak self] in self?.writeRegistry(paths.labRegistry) }
            t.resume()
            registryTimers[paths.labRegistry.path] = t
        }
        regLock.unlock()
        let d = Process()
        d.executableURL = tools.appendingPathComponent("icleard")
        d.environment = ProcessInfo.processInfo.environment.merging(
            ["ICLEAR_HOME": paths.home.path, "ICLEAR_INSTANCE": "lab", "ICLEAR_LAB": "1"].merging(extra) { _, n in n }
        ) { _, n in n }
        d.standardError = FileHandle.nullDevice
        guard (try? d.run()) != nil else { return nil }
        regLock.lock()
        daemons.append(d)
        regLock.unlock()
        for _ in 0..<200 {
            if IPC.send(Request("ping"), path: paths.socket.path, timeout: 1)?.ok == true,
                Proc.table().values.contains(where: { $0.ppid == d.processIdentifier })
            {
                return d
            }
            usleep(25_000)
        }
        return d
    }

    /// Stash/pop soak (C7) against an isolated, scope-locked daemon.
    func stash(cycles: Int, tools: URL) {
        struct Row: Codable {
            var cycles = 0, stashOK = 0, popOK = 0, boundsOK = 0, boundsChecked = 0, frontWanted = 0, frontRestored = 0
            var leftStopped = 0, leftHidden = 0, crashes = 0, hangs = 0, activationPops = 0, activationPopOK = 0, docChanges = 0
            var worstPoints = 0.0
            var popMs: [Double] = []
        }
        var r = Row()
        let since = Date()
        let saved = fixtures
        // System apps (TextEdit, Preview) are in iClear's protected set and are never stashed;
        // two lab GUI apps take their place so that four apps are stashed together.
        let probeApps = stashProbes()
        regLock.lock()
        fixtures = saved.filter { !Lab.isSystemApp($0) } + probeApps
        regLock.unlock()
        defer {
            for p in probeApps { p.kill() }
            regLock.lock()
            fixtures = saved
            regLock.unlock()
        }
        log("stash apps: " + fixtures.map(\.name).joined(separator: ", "))
        for f in fixtures { f.app.unhide() }
        sleep(2)
        let paths = Paths(environment: ["ICLEAR_HOME": labHome("stash").path, "ICLEAR_INSTANCE": "lab"])
        guard let d = startDaemon(paths, tools: tools) else {
            log("stash: daemon did not start")
            return
        }
        defer {
            d.terminate()
            d.waitUntilExit()
        }
        for i in 0..<cycles {
            powerGate()
            writeRegistry(paths.labRegistry)
            let wantFront = fixtures[i % fixtures.count]
            Lab.bringToFront(wantFront)
            let wasFront = NSRunningApplication(processIdentifier: wantFront.pid)?.isActive == true
            let before = fixtures.map { f in
                Dictionary((Windows.windows()[f.pid] ?? []).map { ($0.number, $0.rect) }, uniquingKeysWith: { a, _ in a })
            }
            let s = IPC.send(Request("stash", app: "lab\(i)", value: includeAll), path: paths.socket.path, timeout: 60)
            let allPaused = fixtures.allSatisfy { $0.stopped() && $0.isHidden }
            if s?.ok == true && allPaused {
                r.stashOK += 1
            } else {
                log("stash \(i): \(s?.text.split(separator: "\n").first ?? "no answer"); all paused and hidden: \(allPaused)")
            }
            // Past the daemon's 2 s settle window, in which activations do not pop a stash.
            usleep(UInt32.random(in: 2_500_000...5_000_000))
            // Activating a stashed app (as from the Dock) pops just that app. Only fixtures
            // whose app has no other instance (such as the user's own) are activated this way.
            if i % 5 == 4, let first = fixtures.first(where: { Lab.onlyInstance($0) }), let url = first.app.bundleURL {
                r.activationPops += 1
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                cfg.createsNewApplicationInstance = false
                NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
                var ok = false
                for _ in 0..<60 {
                    if !first.stopped() && !first.isHidden && fixtures.filter({ $0 !== first }).allSatisfy({ $0.stopped() }) {
                        ok = true
                        break
                    }
                    usleep(50_000)
                }
                if ok { r.activationPopOK += 1 } else { log("activation pop \(i): not as expected") }
            }
            let t = Date()
            let p = IPC.send(Request("pop", app: "lab\(i)"), path: paths.socket.path, timeout: 60)
            var back = false
            for _ in 0..<150 {
                if fixtures.allSatisfy({ !$0.stopped() && !$0.isHidden }) {
                    back = true
                    break
                }
                usleep(20_000)
            }
            r.popMs.append(Date().timeIntervalSince(t) * 1000)
            if p?.ok == true && back { r.popOK += 1 }
            r.leftStopped += fixtures.filter { $0.stopped() }.count
            r.leftHidden += fixtures.filter { $0.isHidden }.count
            usleep(800_000)
            for (k, f) in fixtures.enumerated() {
                let after = Dictionary((Windows.windows()[f.pid] ?? []).map { ($0.number, $0.rect) }, uniquingKeysWith: { a, _ in a })
                for (num, rect) in before[k] {
                    guard let a = after[num] else { continue }
                    r.boundsChecked += 1
                    let dpts = rect.distance(to: a)
                    r.worstPoints = max(r.worstPoints, dpts)
                    if dpts <= 4 { r.boundsOK += 1 } else { log("bounds: \(f.name) window \(num) moved \(dpts) pt") }
                }
                if AXIsProcessTrusted(), f.axPing(timeout: 5) == nil { r.hangs += 1 }
                if !f.docsIntact() {
                    r.docChanges += 1
                    log("DATA: a document of \(f.name) changed")
                }
            }
            if wasFront {
                r.frontWanted += 1
                if NSRunningApplication(processIdentifier: wantFront.pid)?.isActive == true {
                    r.frontRestored += 1
                } else {
                    log("frontmost not restored for \(wantFront.name)")
                }
            }
            r.cycles += 1
            if i % 10 == 0 { log("stash cycle \(i + 1)/\(cycles)") }
            // Never leave anything paused between cycles.
            for f in fixtures where f.stopped() { for id in f.tree() { _ = Signals.send(SIGCONT, to: id) } }
        }
        r.crashes = newCrashReports(names: fixtures.map(\.name), since: since).count
        let md = """
            ## Stash and pop (\(r.cycles) cycles, \(fixtures.count) apps: \(fixtures.map(\.name).joined(separator: ", ")))

            | Measure | Result |
            |---|---|
            | Stash: every app paused and hidden | \(r.stashOK)/\(r.cycles) |
            | Pop: every app running and shown within 3 s | \(r.popOK)/\(r.cycles) |
            | Window bounds within 4 points (per window) | \(r.boundsOK)/\(r.boundsChecked), worst \(String(format: "%.1f", r.worstPoints)) pt |
            | Frontmost app restored (when it became frontmost before the stash) | \(r.frontRestored)/\(r.frontWanted) |
            | Apps left paused / hidden after pop | \(r.leftStopped) / \(r.leftHidden) |
            | Activation pops just that app | \(r.activationPopOK)/\(r.activationPops) |
            | Post-pop hangs (no answer in 5 s) | \(AXIsProcessTrusted() ? "\(r.hangs)" : "not measured") |
            | Document changes (SHA-256) | \(r.docChanges) |
            | New crash reports | \(r.crashes) |
            | Pop to all apps shown | \(dist(r.popMs)) |
            """
        save("stash", r, md)
    }

    static func isSystemApp(_ f: AppFixture) -> Bool { f.app.bundleURL?.path.hasPrefix("/System/") ?? false }

    /// Two ic-ui-probe apps wrapped as fixtures (their own bundle IDs, never the user's).
    func stashProbes() -> [AppFixture] {
        let dir = out.appendingPathComponent("stash-probes-\(getpid())")
        let probe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
            .appendingPathComponent("ic-ui-probe").path
        return ["LabProbeA", "LabProbeB"].enumerated().compactMap { i, name in
            guard let g = try? GUIFixture(probe: probe, dir: dir, name: name, frame: i == 0 ? "160,180,360,240" : "560,220,360,240") else {
                return nil
            }
            let f = AppFixture(kind: "probe", name: name, app: g.app, dataDir: dir.appendingPathComponent(name), docs: [])
            regLock.lock()
            everStarted.append(f)
            regLock.unlock()
            return f
        }
    }

    /// Crash recovery (C2): kill -9 the lab daemon while fixtures are frozen or stashed.
    func crash(freezeTrials: Int, stashTrials: Int, tools: URL) {
        struct Row: Codable {
            var freezeOK = 0, freezeTrials = 0, stashOK = 0, stashTrials = 0
            var seconds: [Double] = []
            var stashSeconds: [Double] = []
        }
        var r = Row()
        let all = fixtures
        let probeApps = stashTrials > 0 ? stashProbes() : []
        defer {
            for p in probeApps { p.kill() }
            regLock.lock()
            fixtures = all
            regLock.unlock()
        }
        let paths = Paths(environment: ["ICLEAR_HOME": labHome("crash").path, "ICLEAR_INSTANCE": "lab"])
        for i in 0..<(freezeTrials + stashTrials) {
            powerGate()
            let stash = i >= freezeTrials
            if i == freezeTrials {
                // Stash trials: the stashable apps (system apps are protected) and two lab GUI apps.
                regLock.lock()
                fixtures = all.filter { !Lab.isSystemApp($0) } + probeApps
                regLock.unlock()
            }
            for f in fixtures where f.isHidden != !stash {
                if stash { f.app.unhide() } else { f.app.hide() }
            }
            usleep(stash ? 600_000 : 200_000)
            guard let d = startDaemon(paths, tools: tools) else {
                log("crash: daemon did not start")
                continue
            }
            let dj = JournalStore(url: paths.journal)
            var armed = false
            if stash {
                let r = IPC.send(Request("stash", app: "crash\(i)", value: includeAll), path: paths.socket.path, timeout: 60)
                armed = r?.ok == true && fixtures.allSatisfy { $0.stopped() && $0.isHidden }
                if !armed {
                    log("crash stash trial \(i): \(r?.text.replacingOccurrences(of: "\n", with: " | ").prefix(300) ?? "no answer")")
                }
            } else {
                lockScope()
                armed = fixtures.allSatisfy { f in Signals.freezeTree(f.tree(), appID: f.name, at: 0, journal: dj).ok }
            }
            let t = Date()
            kill(d.processIdentifier, SIGKILL)
            d.waitUntilExit()
            var took = 99.0
            while Date().timeIntervalSince(t) < 5 {
                if fixtures.allSatisfy({ !$0.stopped() && (!stash || !$0.isHidden) }) {
                    took = Date().timeIntervalSince(t)
                    break
                }
                usleep(10_000)
            }
            if stash {
                r.stashTrials += 1
                r.stashSeconds.append(took)
                if armed && took <= 2 { r.stashOK += 1 } else { log("crash stash trial \(i): armed \(armed), recovered after \(took) s") }
            } else {
                r.freezeTrials += 1
                r.seconds.append(took)
                if armed && took <= 2 { r.freezeOK += 1 } else { log("crash freeze trial \(i): armed \(armed), recovered after \(took) s") }
            }
            for f in fixtures { for id in f.tree() { _ = Signals.send(SIGCONT, to: id) } }
            if i % 10 == 0 { log("crash trial \(i + 1)/\(freezeTrials + stashTrials)") }
            usleep(300_000)
        }
        let md = """
            ## Crash recovery: kill -9 of the lab daemon

            | Trials | Recovered within 2 s | Time to recovery |
            |---|---|---|
            | while frozen | \(r.freezeOK)/\(r.freezeTrials) | \(dist(r.seconds.map { $0 * 1000 })) |
            | while stashed (resumed and unhidden) | \(r.stashOK)/\(r.stashTrials) | \(dist(r.stashSeconds.map { $0 * 1000 })) |
            """
        save("crash", r, md)
    }

    /// Paired runs (C8): `measure(on)` returns the probe's p99 and a side-effect value.
    func paired(name: String, pairs: Int, measure: (Bool) -> (p99: Double, side: Double)) -> String {
        struct Pair: Codable {
            var off: Double
            var on: Double
            var offSide: Double
            var onSide: Double
        }
        var ps: [Pair] = []
        for i in 0..<pairs {
            powerGate()
            let first = i % 2 == 0
            let a = measure(first)
            let b = measure(!first)
            let (on, off) = first ? (a, b) : (b, a)
            ps.append(Pair(off: off.p99, on: on.p99, offSide: off.side, onSide: on.side))
            log(String(format: "%@ pair %d/%d: off p99 %.3f, on p99 %.3f", name, i + 1, pairs, off.p99, on.p99))
        }
        let rel = ps.map { $0.off > 0 ? ($0.off - $0.on) / $0.off : 0 }
        var boot: [Double] = []
        for _ in 0..<2000 {
            let s = (0..<rel.count).map { _ in rel.randomElement()! }
            boot.append(percentileOf(s, 0.5))
        }
        let lo = percentileOf(boot, 0.025)
        let hi = percentileOf(boot, 0.975)
        let side = ps.map { $0.offSide > 0 ? ($0.onSide - $0.offSide) / $0.offSide : 0 }
        let md = String(
            format:
                "%@: N=%d pairs; median reduction of p99 %.1f%% (95%% bootstrap interval %.1f%% to %.1f%%); off p99 median %.3f ms, on p99 median %.3f ms; side-effect change median %.1f%%",
            name, ps.count, percentileOf(rel, 0.5) * 100, lo * 100, hi * 100, percentileOf(ps.map(\.off), 0.5),
            percentileOf(ps.map(\.on), 0.5),
            percentileOf(side, 0.5) * 100)
        save(name.replacingOccurrences(of: " ", with: "-"), ps, "### " + md)
        return md
    }
}
