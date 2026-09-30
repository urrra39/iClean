// Phase 0 spike: SIGSTOP/SIGCONT effect on footprint, thaw latency, and
// memory-pressure event timing. It only ever signals ic-hog processes that
// it spawned itself, caps the pressure it induces, and cleans up on exit.
//
// Build: swiftc -O -o freeze_spike spikes/freeze_spike.swift
// Run:   ./freeze_spike <path-to-ic-hog> [pressure-cap-percent-of-RAM]
import Darwin
import Foundation

let hogPath = CommandLine.arguments[1]
let capPercent = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 50
let ramMB = Int(ProcessInfo.processInfo.physicalMemory >> 20)
let maxSwapMB = 1024.0

func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
func ms(_ ns: UInt64) -> Double { Double(ns) / 1e6 }

// MARK: - Spawned hogs (the only processes this spike signals)

final class Hog {
    let proc = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var lines: [(UInt64, String)] = []

    init(_ args: [String]) {
        proc.executableURL = URL(fileURLWithPath: hogPath)
        proc.arguments = args
        proc.standardOutput = pipe
        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self, let s = String(data: h.availableData, encoding: .utf8) else { return }
            buffer += s
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl])
                buffer.removeSubrange(...nl)
                self.lock.lock(); self.lines.append((now(), line)); self.lock.unlock()
            }
        }
        try! proc.run()
        Hog.all.append(self)
    }

    var pid: pid_t { proc.processIdentifier }

    func waitReady() {
        while !snapshot().contains(where: { $0.1.hasPrefix("ready") }) { usleep(10_000) }
    }

    func snapshot() -> [(UInt64, String)] { lock.lock(); defer { lock.unlock() }; return lines }

    /// First line starting with `prefix` whose embedded child timestamp is after `t`.
    func firstStamp(_ prefix: String, after t: UInt64, timeout: Double = 30) -> UInt64? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (_, l) in snapshot() where l.hasPrefix(prefix + " ") {
                if let v = UInt64(l.dropFirst(prefix.count + 1)), v > t { return v }
            }
            usleep(500)
        }
        return nil
    }

    static var all: [Hog] = []
    static func killAll() {
        for h in all where h.proc.isRunning {
            kill(h.pid, SIGCONT)
            kill(h.pid, SIGKILL)
        }
    }
}

atexit { Hog.killAll() }
for s in [SIGINT, SIGTERM, SIGHUP] { signal(s) { _ in Hog.killAll(); exit(1) } }

// MARK: - System readings

func rusage(_ pid: pid_t) -> (resident: Double, footprint: Double) {
    var ri = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &ri) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard rc == 0 else { return (0, 0) }
    return (Double(ri.ri_resident_size) / 1048576, Double(ri.ri_phys_footprint) / 1048576)
}

func vm() -> (compressedMB: Double, swapUsedMB: Double, freeMB: Double) {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    var swap = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
    let page = Double(vm_kernel_page_size)
    return (Double(stats.compressor_page_count) * page / 1048576,
            Double(swap.xsu_used) / 1048576,
            Double(stats.free_count) * page / 1048576)
}

func sysctlInt(_ name: String) -> Int {
    var v: Int32 = 0
    var s = MemoryLayout<Int32>.size
    sysctlbyname(name, &v, &s, nil, 0)
    return Int(v)
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted()
    return s[min(s.count - 1, Int(Double(s.count - 1) * p + 0.5))]
}

func report(_ label: String, _ xs: [Double]) {
    print(String(format: "  %@: n=%d p50=%.2f ms p95=%.2f ms max=%.2f ms", label, xs.count,
                 percentile(xs, 0.5), percentile(xs, 0.95), xs.max()!))
}

// MARK: - 1. Thaw latency without pressure

print("== machine: RAM \(ramMB) MB, pressure level \(sysctlInt("kern.memorystatus_vm_pressure_level")), memorystatus_level \(sysctlInt("kern.memorystatus_level"))%")
print("== thaw latency, no induced pressure (20 freeze/thaw cycles per size)")
for mb in [64, 512, 2048] {
    let h = Hog(["--mb", "\(mb)", "--heartbeat-ms", "1", "--touch-on-cont"])
    h.waitReady()
    var sched: [Double] = [], touched: [Double] = []
    for _ in 0..<20 {
        kill(h.pid, SIGSTOP)
        usleep(200_000)
        let t = now()
        kill(h.pid, SIGCONT)
        if let hb = h.firstStamp("hb", after: t) { sched.append(ms(hb - t)) }
        if let tc = h.firstStamp("touched", after: t) { touched.append(ms(tc - t)) }
        usleep(100_000)
    }
    print(" \(mb) MB hog:")
    report("SIGCONT -> first heartbeat", sched)
    report("SIGCONT -> all pages touched", touched)
    kill(h.pid, SIGKILL)
}

// MARK: - 2. Footprint under induced pressure: frozen vs. running twin

let startLevel = sysctlInt("kern.memorystatus_vm_pressure_level")
guard startLevel == 1 else { print("pressure not normal at start (\(startLevel)); skipping pressure test"); exit(0) }

print("== footprint under induced pressure (cap \(capPercent)% of RAM, abort at critical or swap > \(Int(maxSwapMB)) MB)")
let victimArgs = ["--mb", "1024", "--data", "compressible", "--touch-every", "2", "--heartbeat-ms", "1", "--touch-on-cont"]
let frozen = Hog(victimArgs)
let control = Hog(victimArgs)
frozen.waitReady(); control.waitReady()
usleep(500_000)
kill(frozen.pid, SIGSTOP)

// Pressure events: DispatchSource vs. polling the sysctl every 100 ms.
var events: [(String, UInt64, Int)] = []
let eventsLock = NSLock()
let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global())
source.setEventHandler {
    let d = source.data
    let name = d.contains(.critical) ? "critical" : d.contains(.warning) ? "warning" : "normal"
    eventsLock.lock(); events.append(("dispatch:" + name, now(), 0)); eventsLock.unlock()
}
source.resume()
var lastPolled = startLevel
let poller = DispatchSource.makeTimerSource(queue: .global())
poller.schedule(deadline: .now(), repeating: .milliseconds(100))
poller.setEventHandler {
    let l = sysctlInt("kern.memorystatus_vm_pressure_level")
    if l != lastPolled {
        eventsLock.lock(); events.append(("sysctl:\(l)", now(), l)); eventsLock.unlock()
        lastPolled = l
    }
}
poller.resume()

func sample(_ tag: String) {
    let v = vm()
    let f = rusage(frozen.pid), c = rusage(control.pid)
    print(String(format: "  %-14@ frozen resident %6.0f MB footprint %6.0f | running resident %6.0f footprint %6.0f | compressor %6.0f MB swap %5.0f MB free %6.0f MB level %d",
                 tag, f.resident, f.footprint, c.resident, c.footprint, v.compressedMB, v.swapUsedMB, v.freeMB,
                 sysctlInt("kern.memorystatus_vm_pressure_level")))
}

sample("baseline")
let base = vm()
var pressureHogs: [Hog] = []
let capMB = ramMB * capPercent / 100
var allocated = 0
var aborted: String?
let t0 = now()
while allocated + 512 <= capMB {
    let h = Hog(["--mb", "512", "--data", "random"])
    h.waitReady()
    pressureHogs.append(h)
    allocated += 512
    let v = vm()
    let level = sysctlInt("kern.memorystatus_vm_pressure_level")
    if level >= 4 { aborted = "critical pressure"; break }
    if v.swapUsedMB - base.swapUsedMB > maxSwapMB { aborted = "swap limit"; break }
    if allocated % 2048 == 0 { sample("+\(allocated) MB") }
}
print("  induced \(allocated) MB of incompressible memory in \(String(format: "%.1f", ms(now() - t0) / 1000)) s\(aborted.map { ", aborted: " + $0 } ?? "")")
for i in 1...4 { sleep(5); sample("hold \(i * 5)s") }

// Thaw the frozen victim while pressure is held: its pages may be compressed.
let tc = now()
kill(frozen.pid, SIGCONT)
let hb = frozen.firstStamp("hb", after: tc)
let touchedAt = frozen.firstStamp("touched", after: tc)
print(String(format: "  thaw under pressure: SIGCONT -> heartbeat %.2f ms, -> all 1024 MB touched %.2f ms",
             hb.map { ms($0 - tc) } ?? -1, touchedAt.map { ms($0 - tc) } ?? -1))
sample("after thaw")

for h in pressureHogs { kill(h.pid, SIGKILL) }
sleep(3)
sample("released")
source.cancel(); poller.cancel()
eventsLock.lock()
print("== pressure events (relative to start of pressure induction)")
for (name, t, _) in events { print(String(format: "  %@ at +%.0f ms", name, ms(t - t0))) }
if events.isEmpty { print("  none observed") }
eventsLock.unlock()
