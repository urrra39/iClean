import AppKit
import Foundation
import ICCore

extension Paths {
    /// The brake's own journal: it runs in a separate process and never shares the daemon's.
    public var brakeJournal: URL { base.appendingPathComponent("brake-journal.json") }
    public var brakeSocket: URL { base.appendingPathComponent("icbrake.sock") }
    public var brakeCalibration: URL { base.appendingPathComponent("brake-calibration.json") }
    public var blackBox: URL { base.appendingPathComponent("blackbox.json") }
    public var blackBoxPrevious: URL { base.appendingPathComponent("blackbox-previous.json") }
    public var blackBoxMarker: URL { base.appendingPathComponent("blackbox-marker.json") }
    /// Present after an unclean restart was detected, until `iclear blackbox --dismiss`.
    public var blackBoxUnclean: URL { base.appendingPathComponent("blackbox-unclean.json") }
}

extension Proc {
    /// Page-ins of a same-user process since it started (nil if not readable).
    public static func pageIns(_ pid: Int32) -> UInt64? {
        var ri = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? ri.ri_pageins : nil
    }

    public static func bootTime() -> Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
    }
}

/// Reads the stall signals without allocating: MIBs and the host port are looked up once.
public final class BrakeSignalReader: @unchecked Sendable {
    private var pressureMIB = [Int32](repeating: 0, count: 8)
    private var pressureMIBCount = 8
    private var swapMIB = [Int32](repeating: 0, count: 8)
    private var swapMIBCount = 8
    private let host = mach_host_self()
    private let cores = ProcessInfo.processInfo.activeProcessorCount
    public private(set) var swapMB = 0.0
    public private(set) var compressedMB = 0.0

    public init() {
        sysctlnametomib("kern.memorystatus_vm_pressure_level", &pressureMIB, &pressureMIBCount)
        sysctlnametomib("vm.swapusage", &swapMIB, &swapMIBCount)
    }

    public func read(t: Double, jitterMs: Double) -> StallSignals {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctl(&pressureMIB, u_int(pressureMIBCount), &level, &size, nil, 0)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctl(&swapMIB, u_int(swapMIBCount), &swap, &swapSize, nil, 0)
        swapMB = Double(swap.xsu_used) / 1_048_576
        compressedMB = Double(stats.compressor_page_count) * Double(vm_kernel_page_size) / 1_048_576
        var loads = (0.0, 0.0, 0.0)
        _ = withUnsafeMutablePointer(to: &loads) { $0.withMemoryRebound(to: Double.self, capacity: 3) { getloadavg($0, 1) } }
        return StallSignals(
            t: t, pressure: Int(level), swapIns: stats.swapins, decompressions: stats.decompressions, pageIns: stats.pageins,
            load1: loads.0, cores: cores, jitterMs: jitterMs)
    }
}

/// The status `iclear brake status` and the menu show.
public struct BrakeStatus: Codable, Sendable {
    public var mode: BrakeMode
    public var state: StallState
    public var score: Double
    public var pauses: [BrakePause]
    public var episode: [String]
    public var loopLatencyMs: [Double]  // p50, p95, max over the last 10 minutes
    public var blackBoxSamples: Int
    public var unclean: Bool
}

/// The Panic Brake runtime, in its own process (`icbrake`) with its own LaunchAgent and
/// journal. A time-constraint thread samples the signals every 250 ms into the stall
/// detector and the Black Box ring; everything else (ranking, the ladder, releases, the
/// Black Box file, IPC) runs on the main queue once a second.
public final class BrakeAgent {
    public let paths: Paths
    let probe: Probe
    public let journal: JournalStore
    public var settings: BrakeSettings
    public var clock: () -> Double = { Date().timeIntervalSince1970 }
    let labMode = ProcessInfo.processInfo.environment["ICLEAR_LAB"] == "1"

    // Shared with the sampling thread (under `lock`).
    let lock = NSLock()
    var detector: StallDetector
    var lastSignals: StallSignals?
    var ring = BlackBoxRing()
    var lateness = [Double](repeating: 0, count: 2400)
    var latenessCount = 0
    /// Lab and selftest only: feed a synthetic stall to the detector.
    var simulateStall = false
    /// Read on the main queue every 10 s (reading the power source allocates).
    var onAC = true
    var lastPowerCheck = 0.0

    public internal(set) var ladder: BrakeLadder
    /// Apps the brake keeps paused (the stall cleared with them paused).
    public internal(set) var pauses: [String: (pause: BrakePause, processes: [ProcessIdentity])] = [:]
    var trees: [String: TreeUsage] = [:]
    var lastTreeSample = 0.0
    /// Footprint and page-in readings per app over the last 30 s (growth is measured over the window).
    var usageHistory: [String: [(t: Double, mb: Double, pageIns: UInt64)]] = [:]
    var normalSince: Double?
    var lastFlush = 0.0
    var flushedUpTo = 0.0
    var lastConfigCheck = 0.0
    var configMTime: Date?
    public internal(set) var events: [DaemonEvent] = []
    var server: IPCServer?
    var timer: DispatchSourceTimer?
    var unclean = false

    public init(paths: Paths = Paths(), probe: Probe = LiveProbe()) {
        self.paths = paths
        self.probe = probe
        journal = JournalStore(url: paths.brakeJournal)
        let config = (try? Data(contentsOf: paths.config)).flatMap { try? Config.load(json: $0).0 } ?? Config()
        settings = config.brake
        let calibration = (try? Files.readJSON(StallCalibration.self, from: paths.brakeCalibration)) ?? StallCalibration()
        detector = StallDetector(calibration: calibration)
        ladder = BrakeLadder(settings: settings)
        ring = BlackBoxRing()
    }

    // MARK: lifecycle

    public func start(watchdogExecutable: URL?) throws {
        try paths.ensure()
        // Anything a previous brake process left paused is resumed first.
        _ = Signals.recover(journal: journal)
        checkUncleanRestart()
        if let exe = watchdogExecutable {
            let w = Process()
            w.executableURL = exe
            w.arguments = ["--watchdog", "\(getpid())"]
            try? w.run()
        }
        server = IPCServer(path: paths.brakeSocket.path) { [weak self] in
            self?.handle($0) ?? Response(ok: false, text: "brake shutting down")
        }
        try server?.start()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self.map { $0.work(now: $0.clock()) } }
        t.resume()
        timer = t
        let reader = BrakeSignalReader()
        let thread = Thread { [weak self] in self?.samplingLoop(reader) }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// The previous boot ended without the brake's clean-shutdown marker: keep its Black Box.
    func checkUncleanRestart() {
        let boot = Proc.bootTime()
        let previous = try? Files.readJSON(BlackBoxMarker.self, from: paths.blackBoxMarker)
        if BlackBoxMarker.uncleanRestart(previous: previous, currentBoot: boot), FileManager.default.fileExists(atPath: paths.blackBox.path)
        {
            try? FileManager.default.removeItem(at: paths.blackBoxPrevious)
            try? FileManager.default.moveItem(at: paths.blackBox, to: paths.blackBoxPrevious)
            try? Files.writeJSON(["detectedAt": clock(), "previousBoot": previous?.bootTime ?? 0], to: paths.blackBoxUnclean)
            unclean = true
        }
        unclean = unclean || FileManager.default.fileExists(atPath: paths.blackBoxUnclean.path)
        try? Files.writeJSON(BlackBoxMarker(bootTime: boot, cleanShutdown: false), to: paths.blackBoxMarker)
    }

    /// SIGTERM (logout, restart, `launchctl bootout`): resume every brake pause, flush the
    /// Black Box and mark this boot as cleanly shut down.
    public func shutdown() {
        resumeAll(reason: Code.thawShutdown)
        flushBlackBox(force: true)
        try? Files.writeJSON(BlackBoxMarker(bootTime: Proc.bootTime(), cleanShutdown: true), to: paths.blackBoxMarker)
    }

    // MARK: sampling thread

    func samplingLoop(_ reader: BrakeSignalReader) {
        Self.setTimeConstraint(periodMs: 250)
        let period: UInt64 = 250_000_000
        var next = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + period
        var tick = 0
        while true {
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            if next > now {
                var ts = timespec(tv_sec: 0, tv_nsec: Int(next - now))
                nanosleep(&ts, nil)
            }
            let woke = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let late = Double(woke &- next) / 1e6
            next = max(next + period, woke)
            let s = reader.read(t: Date().timeIntervalSince1970, jitterMs: late)
            ingest(s, swapMB: reader.swapMB, compressedMB: reader.compressedMB, recordBlackBox: tick % 8 == 0, lateMs: late)
            tick &+= 1
        }
    }

    static func setTimeConstraint(periodMs: Double) {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let abs = { (ms: Double) in UInt32(ms * 1_000_000 * Double(tb.denom) / Double(tb.numer)) }
        var pol = thread_time_constraint_policy(period: abs(periodMs), computation: abs(2), constraint: abs(10), preemptible: 1)
        let count = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &pol) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_policy_set(pthread_mach_thread_np(pthread_self()), thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, count)
            }
        }
    }

    /// One reading into the detector (and, every 2 s, the Black Box ring). Tests call it directly.
    public func ingest(_ raw: StallSignals, swapMB: Double = 0, compressedMB: Double = 0, recordBlackBox: Bool = true, lateMs: Double = 0) {
        lock.lock()
        defer { lock.unlock() }
        var s = raw
        if simulateStall {
            let base = lastSignals ?? raw
            s.pressure = 4
            s.swapIns = base.swapIns &+ 10_000
            s.decompressions = base.decompressions &+ 50_000
            s.jitterMs = 500
        }
        lastSignals = s
        detector.update(s)
        lateness[latenessCount % lateness.count] = lateMs
        latenessCount &+= 1
        guard recordBlackBox, settings.blackBox else { return }
        ring.append(
            BlackBoxSample(
                t: s.t, pressure: s.pressure, swapMB: swapMB, compressedMB: compressedMB, swapInsPerSecond: detector.swapInsPerSecond,
                decompressionsPerSecond: detector.decompressionsPerSecond, pageInsPerSecond: detector.pageInsPerSecond, load1: s.load1,
                jitterMs: s.jitterMs, thermal: ProcessInfo.processInfo.thermalState.rawValue, onAC: onAC, state: detector.state,
                score: detector.score))
    }

    // MARK: main-queue work

    public func work(now: Double) {
        lock.lock()
        let state = detector.state
        let recovering = state == .stalled && !detector.conditionNow
        let since = detector.stalledSince
        let pressure = lastSignals?.pressure ?? 1
        lock.unlock()
        if now - lastConfigCheck >= 5 { reloadConfig(now: now) }
        if now - lastPowerCheck >= 10 {
            lastPowerCheck = now
            let battery = SystemSampler.powerState().onBattery
            lock.lock()
            onAC = !battery
            lock.unlock()
        }
        if state != .healthy, now - lastTreeSample >= (state == .stalled ? 1 : 5) { sampleTrees(now: now) }
        if state == .stalled || ladder.inEpisode {
            let ranking = CulpritRanker.rank(Array(trees.values), stalledFor: now - (since ?? now), settings: settings)
            for e in ladder.step(now: now, stalled: state == .stalled, recovering: recovering, ranking: ranking) { apply(e, now: now) }
        }
        normalSince = pressure == 1 ? (normalSince ?? now) : nil
        for (id, p) in pauses {
            if p.pause.releaseDue(now: now, normalSince: normalSince, settings: settings) {
                release(id, reason: Code.panicReleased, note: "released")
            } else if p.pause.quitRequestDue(now: now, settings: settings) {
                pauses[id]?.pause.quitRequested = true
                release(id, reason: Code.panicReleased, note: "resumed to ask it to quit")
                let asked = p.processes.first.flatMap { NSRunningApplication(processIdentifier: $0.pid) }?.terminate() ?? false
                record(id, p.pause.name, kind: .requestQuit, code: Code.panicReleased, "asked to quit (\(asked ? "accepted" : "refused"))")
            }
        }
        flushBlackBox(force: false)
    }

    func reloadConfig(now: Double) {
        lastConfigCheck = now
        let m = (try? FileManager.default.attributesOfItem(atPath: paths.config.path))?[.modificationDate] as? Date
        guard m != configMTime else { return }
        configMTime = m
        guard let c = (try? Data(contentsOf: paths.config)).flatMap({ try? Config.load(json: $0).0 }) else { return }
        settings = c.brake
        ladder.settings = c.brake
        if c.brake.mode != .on { resumeAll(reason: Code.panicReleased) }
    }

    /// Interactive shells and terminal plumbing are never candidates.
    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "login", "tmux", "screen", "ssh", "sshd", "-zsh", "-bash"]

    /// Same-user process trees with footprint growth, page-ins and CPU.
    func sampleTrees(now: Double) {
        lastTreeSample = now
        if labMode { ScopeLock.load(paths.labRegistry) }
        let r = probe.collect(now: now)
        let me = getuid()
        // The brake's own ancestors and children are never candidates.
        var lineage: Set<Int32> = [getpid()]
        var up = getppid()
        while up > 1, lineage.insert(up).inserted { up = r.table[up]?.ppid ?? 1 }
        for (pid, info) in r.table where info.ppid == getpid() { lineage.insert(pid) }
        var units: [(id: String, name: String, processes: [ProcessIdentity], footprintMB: Double, cpu: Double, fg: Bool, protected: Bool)] =
            []
        for a in r.apps where !a.processes.isEmpty {
            let protected = Protection.isProtected(a) || a.isDaemonLineage
            units.append((a.id, a.name, a.processes, a.footprintMB, a.cpuPercent, a.isFrontmost, protected))
            // A runaway started from a terminal (or another protected app) is its own
            // candidate: every process of 50 MB or more except shells and the app itself,
            // with its descendants, ranked by its own footprint so the narrowest one wins.
            guard protected else { continue }
            let members = Set(a.processes.map(\.pid)).subtracting(lineage)
            for p in a.processes.dropFirst() where members.contains(p.pid) {
                guard let info = r.table[p.pid], info.footprintMB >= 50, !Self.shells.contains(info.name) else { continue }
                var sub = [p]
                var queue = [p.pid]
                while let q = queue.popLast() {
                    for (pid, c) in r.table where c.ppid == q && members.contains(pid) {
                        sub.append(c.identity)
                        queue.append(pid)
                    }
                }
                units.append(("proc:\(info.name):\(p.pid)", info.name, sub, info.footprintMB, 0, false, false))
            }
        }
        var out: [String: TreeUsage] = [:]
        for a in units {
            let pageIns = a.processes.compactMap { Proc.pageIns($0.pid) }.reduce(0, +)
            var h = (usageHistory[a.id] ?? []).filter { now - $0.t <= 30 }
            let first = h.first
            let dt = first.map { now - $0.t } ?? 0
            let growth = dt > 0 ? (a.footprintMB - first!.mb) / dt : 0
            let pin = dt > 0 && pageIns >= first!.pageIns ? Double(pageIns - first!.pageIns) / dt : 0
            h.append((now, a.footprintMB, pageIns))
            usageHistory[a.id] = h
            let sameUser = a.processes.allSatisfy { r.table[$0.pid]?.uid ?? me == me }
            let inScope = !labMode || a.processes.allSatisfy { ScopeLock.permits($0) }
            out[a.id] = TreeUsage(
                appID: a.id, name: a.name, processes: a.processes, footprintMB: a.footprintMB, growthMBps: growth, pageInsPerSecond: pin,
                cpuPercent: a.cpu, isForeground: a.fg, isProtected: a.protected, inReach: sameUser && inScope)
        }
        trees = out
        usageHistory = usageHistory.filter { out[$0.key] != nil }
        let top = out.values.filter(\.isSuspect).sorted { $0.culpritScore > $1.culpritScore }.prefix(5).map {
            BlackBoxSample.App(
                id: $0.appID, name: $0.name, footprintMB: $0.footprintMB, growthMBps: $0.growthMBps, pageInsPerSecond: $0.pageInsPerSecond,
                cpuPercent: $0.cpuPercent)
        }
        lock.lock()
        ring.setTop(Array(top))
        lock.unlock()
    }

    func apply(_ e: BrakeEvent, now: Double) {
        let score = String(format: "stall score %.1f", detector.score)
        switch e {
        case .wouldPause(let id):
            record(
                id, trees[id]?.name ?? id, kind: .freeze, code: Code.panicWould, "would have paused it (\(score)); observe mode",
                dryRun: true)
        case .pause(let id):
            guard let t = trees[id], settings.mode == .on else { return }
            let r = Signals.freezeTree(t.processes, appID: id, at: now, journal: journal)
            record(id, t.name, kind: .freeze, code: Code.panicPause, r.ok ? "paused (\(score))" : "could not pause: \(r.error ?? "")")
        case .resume(let id):
            if let t = trees[id] { Signals.thawTree(t.processes, journal: journal) }
            record(id, trees[id]?.name ?? id, kind: .thaw, code: Code.panicResumed, "resumed: the stall went on while it was paused")
        case .confirmed(let id):
            let name = trees[id]?.name ?? id
            pauses[id] = (BrakePause(appID: id, name: name, pausedAt: now), trees[id]?.processes ?? [])
            record(id, name, kind: .freeze, code: Code.panicConfirmed, "kept paused: the stall cleared while it was paused")
            notify("Panic Brake paused \(name)", "The Mac recovered after pausing it. Resume or quit it from the menu.", appID: id)
        case .gaveUp(let why):
            record("", "", kind: .notify, code: Code.panicGaveUp, "still stalled: \(why)")
            notify("Mac still stalled", "The Panic Brake could not clear it (\(why)).", appID: nil)
        }
    }

    func release(_ id: String, reason: String, note: String) {
        guard let p = pauses.removeValue(forKey: id) else { return }
        Signals.thawTree(p.processes, journal: journal)
        record(id, p.pause.name, kind: .thaw, code: reason, note)
    }

    public func resumeAll(reason: String) {
        for id in Array(pauses.keys) { release(id, reason: reason, note: "resumed") }
        if let c = ladder.current, let t = trees[c] { Signals.thawTree(t.processes, journal: journal) }
        _ = Signals.recover(journal: journal)
    }

    /// An activation of a paused app (from the menu, the Dock or app switching) resumes it.
    public func handleActivation(pid: Int32) {
        if let id = pauses.first(where: { $0.value.processes.contains { $0.pid == pid } })?.key {
            release(id, reason: Code.thawActivated, note: "resumed on activation")
        }
    }

    func record(_ id: String, _ name: String, kind: ActionKind, code: String, _ message: String, dryRun: Bool = false) {
        let a = Action(
            kind: kind, appID: id, name: name, processes: trees[id]?.processes ?? [], reasons: [Reason(code, message)], dryRun: dryRun,
            message: "Panic Brake: \(name.isEmpty ? "" : name + " ")\(message)")
        ActionLog.append(ActionLogEntry(t: clock(), action: a, outcome: "ok"), paths: paths)
    }

    func notify(_ title: String, _ body: String, appID: String?) {
        events.append(DaemonEvent(t: clock(), title: title, body: body, appID: appID))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }

    // MARK: Black Box file

    /// Written atomically (a new file renamed over the old one), only while the ring holds
    /// a sample that is not healthy, at most every 5 s, and never larger than 1 MB.
    func flushBlackBox(force: Bool) {
        let now = clock()
        guard settings.blackBox, force || now - lastFlush >= 5 else { return }
        lock.lock()
        let snapshot = ring
        lock.unlock()
        guard let newest = snapshot.samples.last?.t, newest > flushedUpTo, force || !snapshot.healthy else { return }
        lastFlush = now
        var samples = snapshot.samples
        var data = (try? JSONEncoder().encode(samples)) ?? Data()
        while data.count > 1 << 20 && samples.count > 10 {
            samples.removeFirst(samples.count / 4)
            data = (try? JSONEncoder().encode(samples)) ?? Data()
        }
        try? Files.atomicWrite(data, to: paths.blackBox)
        flushedUpTo = newest
    }

    // MARK: IPC

    public func status() -> BrakeStatus {
        lock.lock()
        let n = min(latenessCount, lateness.count)
        let l = Array(lateness.prefix(n)).sorted()
        let state = detector.state
        let score = detector.score
        let samples = ring.samples.count
        lock.unlock()
        func q(_ x: Double) -> Double { l.isEmpty ? 0 : l[min(l.count - 1, Int(Double(l.count - 1) * x))] }
        return BrakeStatus(
            mode: settings.mode, state: state, score: score, pauses: pauses.values.map(\.pause).sorted { $0.pausedAt < $1.pausedAt },
            episode: ladder.tried, loopLatencyMs: [q(0.5), q(0.95), l.last ?? 0], blackBoxSamples: samples, unclean: unclean)
    }

    public func handle(_ req: Request) -> Response {
        switch req.cmd {
        case "ping": return Response(ok: true, text: "pong")
        case "status":
            let s = status()
            return Response(ok: true, text: "", data: String(decoding: (try? JSONEncoder().encode(s)) ?? Data(), as: UTF8.self))
        case "events":
            let since = Double(req.value ?? "0") ?? 0
            let e = events.filter { $0.t > since }
            return Response(ok: true, text: "", data: String(decoding: (try? JSONEncoder().encode(e)) ?? Data(), as: UTF8.self))
        case "resume":
            let q = (req.app ?? "").lowercased()
            if q == "all" {
                resumeAll(reason: Code.thawUser)
                return Response(ok: true, text: "Resumed every app the Panic Brake paused.")
            }
            guard let id = pauses.first(where: { $0.key.lowercased() == q || $0.value.pause.name.lowercased() == q })?.key else {
                return Response(ok: false, text: "The Panic Brake has not paused \(req.app ?? "that app").")
            }
            release(id, reason: Code.thawUser, note: "resumed by the user")
            return Response(ok: true, text: "Resumed \(id).")
        case "quit":
            let q = (req.app ?? "").lowercased()
            guard let (id, p) = pauses.first(where: { $0.key.lowercased() == q || $0.value.pause.name.lowercased() == q }) else {
                return Response(ok: false, text: "The Panic Brake has not paused \(req.app ?? "that app").")
            }
            release(id, reason: Code.thawUser, note: "resumed to ask it to quit")
            let asked = p.processes.first.flatMap { NSRunningApplication(processIdentifier: $0.pid) }?.terminate() ?? false
            return Response(
                ok: asked,
                text: asked ? "Asked \(p.pause.name) to quit (its own Quit)." : "\(p.pause.name) did not accept the quit request.")
        case "trees":
            let t = trees.values.sorted { $0.culpritScore > $1.culpritScore }
            return Response(ok: true, text: "", data: String(decoding: (try? JSONEncoder().encode(t)) ?? Data(), as: UTF8.self))
        case "simulate":
            guard labMode else { return Response(ok: false, text: "Only in lab mode (ICLEAR_LAB=1).") }
            lock.lock()
            simulateStall = req.value == "on"
            lock.unlock()
            return Response(ok: true, text: "Simulated stall \(req.value == "on" ? "on" : "off").")
        default:
            return Response(ok: false, text: "unknown brake command \(req.cmd)")
        }
    }
}

public enum BlackBox {
    /// "Previous shutdown cause" as the unified log states it, if a user can read it.
    /// Codes are shown as logged, not interpreted.
    public static func previousShutdownCause() -> String {
        let boot = Proc.bootTime()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = [
            "show", "--start", f.string(from: Date(timeIntervalSince1970: boot - 60)), "--end",
            f.string(from: Date(timeIntervalSince1970: boot + 600)), "--predicate", "eventMessage CONTAINS \"Previous shutdown cause\"",
            "--style", "compact",
        ]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "Previous shutdown cause: the system log could not be read." }
        p.waitUntilExit()
        let line = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
            .first { $0.contains("Previous shutdown cause") }
        return line.map {
            "macOS logged: \($0.trimmingCharacters(in: .whitespaces)) (the code is shown as logged; its meaning is not documented here)."
        }
            ?? "Previous shutdown cause: not readable without administrator rights on this Mac (kernel messages are not visible to a user)."
    }
}
