// ic-lab: iClear's validation harness. It starts its own fixtures (ic-hog,
// ic-ui-probe, ic-call-sim, and real apps with throwaway data), registers them, and
// only ever signals what it registered. Subcommands print results for
// docs/FEASIBILITY.md and docs/VALIDATION.md.
import AppKit
import ApplicationServices
import Foundation
import ICCore
import ICSystem

setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
let products = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
func tool(_ name: String) -> String { products.appendingPathComponent(name).path }
func pump(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
atexit { SpawnedHog.killAll() }
for s in [SIGINT, SIGTERM, SIGHUP] {
    signal(s) { _ in
        SpawnedHog.killAll()
        exit(1)
    }
}

func spawn(_ path: String, _ args: [String]) -> SpawnedHog {
    let h = try! SpawnedHog(path: path, args: args)
    precondition(h.waitReady(timeout: 60), "fixture did not start: \(path)")
    return h
}

func cpuSeconds(_ pid: Int32) -> Double { Double(Proc.info(pid)?.cpuNanos ?? 0) / 1e9 }

/// "stats n=.. p50=.. p95=.. p99=.. max=.." from a probe, after `after`.
func lastStats(_ h: SpawnedHog) -> String { h.snapshot().last { $0.hasPrefix("stats") } ?? "no stats" }

func statsAfterSignal(_ h: SpawnedHog) -> String {
    let n = h.snapshot().filter { $0.hasPrefix("stats") }.count
    kill(h.pid, SIGUSR1)
    for _ in 0..<200 where h.snapshot().filter({ $0.hasPrefix("stats") }).count == n { usleep(10_000) }
    return lastStats(h)
}

let cores = ProcessInfo.processInfo.activeProcessorCount

/// Thread info for a same-user process (PROC_PIDLISTTHREADS returns handles for PROC_PIDTHREADINFO).
func threadInfos(_ pid: Int32) -> [proc_threadinfo] {
    var handles = [UInt64](repeating: 0, count: 512)
    let n = Int(proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, &handles, Int32(handles.count * 8))) / 8
    return handles.prefix(max(0, n)).compactMap { h in
        var ti = proc_threadinfo()
        let sz = Int32(MemoryLayout<proc_threadinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTHREADINFO, h, &ti, sz) == sz ? ti : nil
    }
}

switch CommandLine.arguments.dropFirst().first ?? "" {
case "signals":
    // Spike (c): which call signals are visible without extra permissions.
    func show(_ tag: String, _ pid: Int32?) {
        let a = AudioActivity.pids()
        print(
            "\(tag): camera=\(Camera.inUse()) micRunningSomewhere=\(AudioActivity.microphoneInUse()) inputPIDs=\(a.input.count) outputPIDs=\(a.output.count)"
                + (pid.map { " call-sim in input set=\(a.input.contains($0))" } ?? ""))
    }
    print("per-process audio attribution available (macOS 14.2+): \(AudioActivity.available)")
    show("before", nil)
    let sim = spawn(tool("ic-call-sim"), ["--audio", "--report", "1"])
    var detected: Double?
    let t0 = Date()
    for _ in 0..<100 {
        if AudioActivity.pids().input.contains(sim.pid) {
            detected = Date().timeIntervalSince(t0)
            break
        }
        usleep(50_000)
    }
    show("call-sim running", sim.pid)
    print("call-sim output: \(sim.snapshot().filter { $0.hasPrefix("audio") || $0.hasPrefix("stats") }.suffix(3))")
    print(
        detected.map { String(format: "call-sim PID attributed to input after %.2f s", $0) }
            ?? "call-sim PID never appeared in the input set within 5 s")
    sim.kill()
    let t1 = Date()
    var cleared: Double?
    for _ in 0..<100 {
        if !AudioActivity.microphoneInUse() {
            cleared = Date().timeIntervalSince(t1)
            break
        }
        usleep(50_000)
    }
    show("after stop", nil)
    print(
        cleared.map { String(format: "mic-in-use cleared %.2f s after the process exited", $0) }
            ?? "mic-in-use still set 5 s after exit (another app may be using it)")

case "energy":
    // Spike (d): per-process energy counters and battery power readings.
    let spin = spawn(tool("ic-hog"), ["--cpu"])
    let e0 = processEnergyNJ(spin.pid)
    let c0 = cpuSeconds(spin.pid)
    let t0 = Date()
    sleep(5)
    let e1 = processEnergyNJ(spin.pid)
    let c1 = cpuSeconds(spin.pid)
    let dt = Date().timeIntervalSince(t0)
    print(
        String(
            format: "ri_energy_nj for one spinning core: %@ -> %.2f W over %.1f s (CPU %.2f cores)",
            "\(e0 ?? 0)..\(e1 ?? 0)", Double((e1 ?? 0) &- (e0 ?? 0)) / 1e9 / dt, dt, (c1 - c0) / dt))
    spin.kill()
    let keys = (SmartBattery.properties() ?? [:]).keys.filter {
        [
            "Voltage", "Amperage", "InstantAmperage", "CurrentCapacity", "MaxCapacity", "AppleRawCurrentCapacity", "AppleRawMaxCapacity",
            "ExternalConnected", "PowerTelemetryData", "NominalChargeCapacity", "DesignCapacity",
        ].contains($0)
    }.sorted()
    print("AppleSmartBattery readable keys: \(keys)")
    func sample(_ seconds: Int) -> [Double] {
        (0..<seconds).compactMap { _ in
            sleep(1)
            return SmartBattery().read(now: Date().timeIntervalSince1970)?.dischargeW
        }
    }
    var updates: [Double] = []
    var lastUpdate = 0.0
    for _ in 0..<90 {
        if let u = (SmartBattery.properties()?["UpdateTime"] as? NSNumber)?.doubleValue, u != lastUpdate {
            if lastUpdate > 0 { updates.append(u - lastUpdate) }
            lastUpdate = u
        }
        sleep(1)
    }
    print("battery UpdateTime intervals over 90 s: \(updates.map { Int($0) }) s")
    if let r = SmartBattery().read(now: Date().timeIntervalSince1970) {
        print(
            String(
                format: "battery: onAC=%@ %.0f%% remaining %.1f Wh discharge %.2f W", "\(r.onAC)", r.percent, r.remainingWh, r.dischargeW))
        if !r.onAC {
            let idle = sample(20)
            let load = (0..<cores).map { _ in spawn(tool("ic-hog"), ["--cpu"]) }
            let busy = sample(20)
            for h in load { h.kill() }
            func m(_ x: [Double]) -> Double { x.sorted()[x.count / 2] }
            print(String(format: "battery power median, idle 20 s: %.2f W; with %d spinning cores 20 s: %.2f W", m(idle), cores, m(busy)))
        }
    } else {
        print("no AppleSmartBattery service (desktop Mac?)")
    }

case "prio":
    // Spike (e): PRIO_DARWIN_BG effects on CPU and disk I/O, and how to read the state back.
    func threadPriorities(_ pid: Int32) -> [Int32] {
        threadInfos(pid).map(\.pth_curpri)
    }
    let load = (0..<cores).map { _ in spawn(tool("ic-hog"), ["--cpu"]) }
    let target = spawn(tool("ic-hog"), ["--cpu"])
    func share(_ seconds: UInt32) -> Double {
        let c0 = cpuSeconds(target.pid)
        let t0 = Date()
        sleep(seconds)
        return (cpuSeconds(target.pid) - c0) / Date().timeIntervalSince(t0)
    }
    print("thread priorities normal: \(threadPriorities(target.pid)) getpriority=\(getpriority(PRIO_DARWIN_PROCESS, id_t(target.pid)))")
    let normal = share(8)
    setpriority(PRIO_DARWIN_PROCESS, id_t(target.pid), PRIO_DARWIN_BG)
    usleep(200_000)
    print("thread priorities BG: \(threadPriorities(target.pid)) getpriority=\(getpriority(PRIO_DARWIN_PROCESS, id_t(target.pid)))")
    let bg = share(8)
    setpriority(PRIO_DARWIN_PROCESS, id_t(target.pid), 0)
    usleep(200_000)
    print("thread priorities restored: \(threadPriorities(target.pid))")
    print(
        String(
            format: "CPU share of one spinner among %d competing spinners: normal %.2f cores, background band %.2f cores", cores, normal, bg
        ))
    for h in load { h.kill() }
    target.kill()
    // Disk: two writers; one in the background band.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ic-lab-io-\(getpid())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func ddRun(background: Bool) -> Double {
        let mk = { (name: String) -> Process in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/dd")
            p.arguments = ["if=/dev/zero", "of=\(dir.appendingPathComponent(name).path)", "bs=1m", "count=2048", "oflag=sync"]
            p.standardError = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            return p
        }
        let a = mk("a")
        let b = mk("b")
        try? a.run()
        try? b.run()
        if background { setpriority(PRIO_DARWIN_PROCESS, id_t(b.processIdentifier), PRIO_DARWIN_BG) }
        let t0 = Date()
        b.waitUntilExit()
        let tb = Date().timeIntervalSince(t0)
        a.waitUntilExit()
        return 2048 / tb
    }
    let ioNormal = ddRun(background: false)
    let ioBG = ddRun(background: true)
    print(
        String(
            format: "disk write throughput of a 2 GB writer competing with another: normal %.0f MB/s, background band %.0f MB/s", ioNormal,
            ioBG))
    print("network effect: not measured (the lab makes no network connections)")

case "stall":
    // Spike (f): what a main-thread heartbeat shows, and what libproc thread states show.
    let probe = spawn(tool("ic-ui-probe"), ["--frame", "80,80,300,200", "--title", "ic-lab stall", "--heartbeat"])
    sleep(10)
    print("idle 10 s: \(statsAfterSignal(probe))")
    let load = (0..<(cores * 2)).map { _ in spawn(tool("ic-hog"), ["--cpu"]) }
    var running = 0
    var total = 0
    for _ in 0..<100 {
        if let main = threadInfos(probe.pid).first {
            total += 1
            if main.pth_run_state == TH_STATE_RUNNING { running += 1 }
        }
        usleep(100_000)
    }
    print("contention (\(cores * 2) spinners) 10 s: \(statsAfterSignal(probe))")
    print(
        "main thread sampled RUNNING in \(running) of \(total) samples (libproc cannot tell a blocked main thread from an idle one: both are WAITING)"
    )
    for h in load { h.kill() }
    print("Accessibility round trip: " + (AXIsProcessTrusted() ? "available" : "not run (Accessibility not granted to this process)"))
    probe.kill()

case "session":
    let ctx = SessionProbe.context(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier, windows: Windows.facts())
    print(
        "camera=\(ctx.cameraInUse) mic=\(ctx.microphoneInUse) screenSharing=\(ctx.screenSharing) mirrored=\(ctx.displayMirrored) fullscreen=\(ctx.frontmostFullscreen)"
    )
    print(
        "sharing processes present: \(SessionProbe.allProcessNames().intersection(["screensharingd", "CptHost", "ScreenSharingSubscriber"]))"
    )

default:
    print("usage: ic-lab signals | energy | prio | stall | session")
}
