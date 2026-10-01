import Darwin
import Foundation
import ICCore

/// An `ic-hog` process spawned by iClean's own tests and benchmarks. These are the
/// only processes that tests and benchmarks ever signal.
public final class SpawnedHog {
    public let process = Process()
    private let lock = NSLock()
    private var lines: [String] = []
    private var buffer = ""

    public init(path: String, args: [String]) throws {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self else { return }
            let s = String(decoding: h.availableData, as: UTF8.self)
            self.lock.lock()
            self.buffer += s
            var parts = self.buffer.components(separatedBy: "\n")
            self.buffer = parts.removeLast()
            self.lines += parts
            self.lock.unlock()
        }
        try process.run()
        Self.liveLock.lock()
        Self.live.insert(process.processIdentifier)
        Self.liveLock.unlock()
    }

    public var pid: Int32 { process.processIdentifier }
    public var identity: ProcessIdentity? { Proc.startTime(pid).map { ProcessIdentity(pid: pid, startTime: $0) } }

    public func waitReady(timeout: Double = 30) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if snapshot().contains(where: { $0.hasPrefix("ready") }) { return true }
            usleep(5000)
        }
        return false
    }

    public func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    /// First `<prefix> <uptime ns>` line stamped after `after` (CLOCK_UPTIME_RAW ns).
    public func stamp(_ prefix: String, after: UInt64, timeout: Double = 30) -> UInt64? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            for l in snapshot() where l.hasPrefix(prefix + " ") {
                if let v = UInt64(l.dropFirst(prefix.count + 1)), v > after { return v }
            }
            usleep(200)
        }
        return nil
    }

    public var residentMB: Double { Proc.info(pid)?.residentMB ?? 0 }

    public func kill() {
        guard pid > 0 else { return }  // kill(0, ...) would signal our own process group
        Darwin.kill(pid, SIGCONT)
        Darwin.kill(pid, SIGKILL)
        process.waitUntilExit()
        Self.liveLock.lock()
        Self.live.remove(pid)
        Self.liveLock.unlock()
    }

    /// Hogs still alive; killed by `killAll()` on exit paths. Tests spawn from many threads.
    nonisolated(unsafe) static var live = Set<Int32>()
    static let liveLock = NSLock()
    public static func killAll() {
        liveLock.lock()
        defer { liveLock.unlock() }
        for p in live where p > 0 {
            Darwin.kill(p, SIGCONT)
            Darwin.kill(p, SIGKILL)
        }
        live.removeAll()
    }
}

public func uptimeNanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

public struct Stat: Codable, Sendable {
    public var n: Int
    public var p50: Double
    public var p95: Double
    public var p99: Double
    public var max: Double

    public init?(_ xs: [Double]) {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        func p(_ q: Double) -> Double { s[Swift.min(s.count - 1, Int((Double(s.count - 1) * q).rounded()))] }
        n = s.count
        p50 = p(0.5)
        p95 = p(0.95)
        p99 = p(0.99)
        max = s.last!
    }

    public var row: String { String(format: "%.2f | %.2f | %.2f | %.2f | %d", p50, p95, p99, max, n) }
}

public enum Bench {
    public struct Result: Codable, Sendable {
        public var date: String
        public var hardware: Hardware
        public var stats: [String: Stat] = [:]
        public var values: [String: Double] = [:]
        public var notes: [String] = []

        public var json: String {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: (try? e.encode(self)) ?? Data(), as: UTF8.self)
        }

        public var markdown: String {
            var l = [
                "Machine: \(hardware.model), \(hardware.arch), \(Int(hardware.memoryGB.rounded())) GB, macOS \(hardware.osVersion). Date: \(date).",
                "",
                "| Measurement | p50 | p95 | p99 | max | n |", "|---|---|---|---|---|---|",
            ]
            for (k, s) in stats.sorted(by: { $0.key < $1.key }) { l.append("| \(k) | \(s.row) |") }
            if !values.isEmpty {
                l += ["", "| Value | Measured |", "|---|---|"]
                for (k, v) in values.sorted(by: { $0.key < $1.key }) { l.append(String(format: "| %@ | %.2f |", k, v)) }
            }
            if !notes.isEmpty { l += [""] + notes.map { "- \($0)" } }
            return l.joined(separator: "\n")
        }
    }

    static func ms(_ ns: UInt64) -> Double { Double(ns) / 1e6 }

    public static func run(hogPath: String, quick: Bool, log: (String) -> Void) -> Result {
        atexit { SpawnedHog.killAll() }
        for s in [SIGINT, SIGTERM, SIGHUP] {
            signal(s) { _ in
                SpawnedHog.killAll()
                exit(1)
            }
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        var r = Result(date: f.string(from: Date()), hardware: SystemSampler.hardware())
        thawLatency(&r, hogPath: hogPath, quick: quick, log: log)
        overhead(&r, quick: quick, log: log)
        pressure(&r, hogPath: hogPath, quick: quick, log: log)
        SpawnedHog.killAll()
        return r
    }

    /// SIGCONT to first heartbeat and to all pages touched, no induced pressure.
    static func thawLatency(_ r: inout Result, hogPath: String, quick: Bool, log: (String) -> Void) {
        for mb in quick ? [256] : [256, 1024] {
            log("thaw latency, \(mb) MB hog")
            guard let h = try? SpawnedHog(path: hogPath, args: ["--mb", "\(mb)", "--heartbeat-ms", "1", "--touch-on-cont"]),
                h.waitReady()
            else {
                r.notes.append("could not start ic-hog")
                return
            }
            var hb: [Double] = []
            var all: [Double] = []
            for _ in 0..<(quick ? 5 : 30) {
                kill(h.pid, SIGSTOP)
                usleep(200_000)
                let t = uptimeNanos()
                kill(h.pid, SIGCONT)
                if let x = h.stamp("hb", after: t) { hb.append(ms(x - t)) }
                if let x = h.stamp("touched", after: t) { all.append(ms(x - t)) }
                usleep(50_000)
            }
            r.stats["thaw, no pressure, \(mb) MB: SIGCONT to running (ms)"] = Stat(hb)
            r.stats["thaw, no pressure, \(mb) MB: SIGCONT to all pages touched (ms)"] = Stat(all)
            h.kill()
        }
    }

    /// Cost of one daemon sampling tick and of the S4 guard inspection.
    static func overhead(_ r: inout Result, quick: Bool, log: (String) -> Void) {
        log("daemon tick overhead")
        let collector = AppCollector()
        _ = collector.collect()
        var cpu: [Double] = []
        var wall: [Double] = []
        var guardMs: [Double] = []
        let engine = Engine(config: Config(), hardware: r.hardware, state: EngineState(startedAt: 0))
        for _ in 0..<(quick ? 3 : 10) {
            var u0 = rusage()
            var u1 = rusage()
            getrusage(RUSAGE_SELF, &u0)
            let t = uptimeNanos()
            let res = collector.collect()
            _ = SystemSampler.sample()
            wall.append(ms(uptimeNanos() - t))
            getrusage(RUSAGE_SELF, &u1)
            func sec(_ tv: timeval) -> Double { Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6 }
            cpu.append((sec(u1.ru_utime) + sec(u1.ru_stime) - sec(u0.ru_utime) - sec(u0.ru_stime)) * 1000)
            let t2 = uptimeNanos()
            for var a in res.apps.filter(\.isRegularApp) { AppCollector.inspectGuards(&a, engine: engine, now: 0) }
            guardMs.append(ms(uptimeNanos() - t2))
            usleep(500_000)
        }
        r.stats["daemon tick: wall time (ms)"] = Stat(wall)
        r.stats["daemon tick: CPU time (ms)"] = Stat(cpu)
        r.stats["S4 guard inspection of every regular app (ms)"] = Stat(guardMs)
        if let p50 = Stat(cpu)?.p50 { r.values["daemon CPU % at the 15 s idle interval (from tick CPU p50)"] = p50 / 15_000 * 100 }
        if let d = Proc.table().values.first(where: { $0.name == "icleand" }) {
            r.values["running icleand resident memory (MB)"] = d.residentMB
        }
    }

    /// Frozen vs running twin under bounded induced pressure, thaw under pressure,
    /// staged vs simultaneous thaw (S7) and pre-thaw (S3).
    static func pressure(_ r: inout Result, hogPath: String, quick: Bool, log: (String) -> Void) {
        let start = SystemSampler.sample()
        guard start.pressure == .normal else {
            r.notes.append("pressure scenarios skipped: pressure was \(start.pressure.name) at start")
            return
        }
        let capMB = start.physicalMB * (quick ? 0.25 : 0.4)
        let maxSwapGrowthMB = 768.0
        func spawn(_ args: [String]) -> SpawnedHog? {
            guard let h = try? SpawnedHog(path: hogPath, args: args), h.waitReady(timeout: 60) else { return nil }
            return h
        }
        let victim = ["--mb", "512", "--data", "compressible", "--touch-every", "2", "--heartbeat-ms", "1", "--touch-on-cont"]
        let small = ["--mb", "128", "--data", "compressible", "--heartbeat-ms", "1"]
        guard let frozen = spawn(victim), let control = spawn(victim) else {
            r.notes.append("could not start victims")
            return
        }
        let simultaneous = (0..<4).compactMap { _ in spawn(small) }
        let staged = (0..<4).compactMap { _ in spawn(small) }
        let cold = spawn(["--mb", "256", "--data", "compressible", "--heartbeat-ms", "1"])
        let prethaw = spawn(["--mb", "256", "--data", "compressible", "--heartbeat-ms", "1"])
        let frozenSet = [frozen] + simultaneous + staged + [cold, prethaw].compactMap { $0 }
        usleep(500_000)
        for h in frozenSet { kill(h.pid, SIGSTOP) }
        let baseline = (frozen: frozen.residentMB, control: control.residentMB)
        r.values["pressure: victim resident before (MB)"] = baseline.frozen

        // Add incompressible memory until the frozen victim is mostly compressed, or a limit.
        log("inducing bounded memory pressure (cap \(Int(capMB)) MB, abort on critical or +\(Int(maxSwapGrowthMB)) MB swap)")
        var pressureHogs: [SpawnedHog] = []
        var induced = 1024.0 + 1024 + 512
        var abort: String?
        var transitions: [String] = []
        var lastLevel = PressureLevel.normal
        func check() -> String? {
            let s = SystemSampler.sample()
            if s.pressure != lastLevel {
                transitions.append("\(lastLevel.name) -> \(s.pressure.name) at \(s.availablePercent)% available")
                lastLevel = s.pressure
            }
            if s.pressure == .critical { return "critical pressure" }
            if s.swapUsedMB - start.swapUsedMB > maxSwapGrowthMB { return "swap limit" }
            return nil
        }
        while induced + 256 <= capMB, frozen.residentMB > baseline.frozen * 0.2 {
            guard let h = spawn(["--mb", "256", "--data", "random"]) else { break }
            pressureHogs.append(h)
            induced += 256
            if let a = check() {
                abort = a
                break
            }
        }
        for _ in 0..<10 where abort == nil {
            sleep(1)
            abort = check()
        }
        let compressed = frozen.residentMB
        r.values["pressure: memory induced incl. victims (MB)"] = induced
        r.values["pressure: frozen victim resident after (MB)"] = compressed
        r.values["pressure: running twin resident after (MB)"] = control.residentMB
        r.notes.append(
            "pressure run: "
                + (abort.map { "stopped early (\($0))" }
                    ?? (compressed <= baseline.frozen * 0.2 ? "frozen victim compressed" : "cap reached before compression")))
        r.notes += transitions.map { "pressure transition: \($0)" }

        // Thaw under pressure.
        var t = uptimeNanos()
        kill(frozen.pid, SIGCONT)
        if let x = frozen.stamp("touched", after: t) {
            r.values["thaw under pressure, 512 MB victim: SIGCONT to all pages touched (ms)"] = ms(x - t)
        }

        // S3 pre-thaw: resume early vs. resume when the user arrives.
        if let cold, let prethaw {
            t = uptimeNanos()
            kill(cold.pid, SIGCONT)
            kill(cold.pid, SIGUSR2)
            if let x = cold.stamp("touched", after: t) { r.values["S3 cold thaw: user arrival to working set back (ms)"] = ms(x - t) }
            kill(prethaw.pid, SIGCONT)
            sleep(2)
            t = uptimeNanos()
            kill(prethaw.pid, SIGUSR2)
            if let x = prethaw.stamp("touched", after: t) {
                r.values["S3 pre-thawed 2 s early: user arrival to working set back (ms)"] = ms(x - t)
            }
        }

        // S7: four apps at once vs. one after another.
        t = uptimeNanos()
        for h in simultaneous {
            kill(h.pid, SIGCONT)
            kill(h.pid, SIGUSR2)
        }
        let simDone = simultaneous.compactMap { $0.stamp("touched", after: t) }
        if simDone.count == simultaneous.count, let first = simDone.min(), let last = simDone.max() {
            r.values["S7 simultaneous thaw of 4: first app usable (ms)"] = ms(first - t)
            r.values["S7 simultaneous thaw of 4: all usable (ms)"] = ms(last - t)
        }
        t = uptimeNanos()
        var stagedDone: [UInt64] = []
        for h in staged {
            let s = uptimeNanos()
            kill(h.pid, SIGCONT)
            kill(h.pid, SIGUSR2)
            if let x = h.stamp("touched", after: s) { stagedDone.append(x) }
        }
        if stagedDone.count == staged.count, let first = stagedDone.min(), let last = stagedDone.max() {
            r.values["S7 staged thaw of 4: first app usable (ms)"] = ms(first - t)
            r.values["S7 staged thaw of 4: all usable (ms)"] = ms(last - t)
        }

        for h in pressureHogs { h.kill() }
        for h in frozenSet + [control] { h.kill() }
        let end = SystemSampler.sample()
        r.values["pressure: swap growth during run (MB)"] = max(0, end.swapUsedMB - start.swapUsedMB)
    }
}
