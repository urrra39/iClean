// Phase P spike (b): after freezing fixtures, how fast does memory actually become
// available to others, with no pressure and with bounded induced pressure? Only
// ic-hog processes started here are signalled; pressure is capped and aborts on
// critical pressure or swap growth.
//
// Build: swiftc -O -o memory_spike spikes/memory_spike.swift
// Run:   ./memory_spike <path-to-ic-hog> [cap-percent]
import Darwin
import Foundation

let hogPath = CommandLine.arguments[1]
let capPercent = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 40
var hogs: [Process] = []
func spawn(_ args: [String]) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: hogPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    try! p.run()
    hogs.append(p)
    // wait for "ready"
    var buf = Data()
    while !String(decoding: buf, as: UTF8.self).contains("ready") { buf += pipe.fileHandleForReading.availableData }
    return p
}
atexit { for h in hogs { kill(h.processIdentifier, SIGCONT); kill(h.processIdentifier, SIGKILL) } }
for s in [SIGINT, SIGTERM] { signal(s) { _ in exit(1) } }

func resident(_ pid: Int32) -> Double {
    var ri = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &ri) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) } }
    return Double(ri.ri_resident_size) / 1_048_576
}
func sysctlInt(_ n: String) -> Int { var v: Int32 = 0; var s = 4; sysctlbyname(n, &v, &s, nil, 0); return Int(v) }
func vm() -> (availMB: Double, compressedMB: Double, swapMB: Double) {
    var st = vm_statistics64()
    var c = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &st) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c) } }
    var sw = xsw_usage(); var sz = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &sw, &sz, nil, 0)
    let pg = Double(vm_kernel_page_size) / 1_048_576
    // "available" as free + inactive + speculative + purgeable pages
    let avail = Double(UInt64(st.free_count) + UInt64(st.inactive_count) + UInt64(st.speculative_count) + UInt64(st.purgeable_count)) * pg
    return (avail, Double(st.compressor_page_count) * pg, Double(sw.xsu_used) / 1_048_576)
}

let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
let start = Date()
func line(_ tag: String, _ frozen: [Process], _ twin: Process) {
    let v = vm()
    let fr = frozen.map { resident($0.processIdentifier) }.reduce(0, +)
    print(String(format: "%6.0fs %-10@ frozen resident %6.0f MB | running twin %5.0f MB | available %6.0f MB (level %d%%) | compressed %6.0f MB | swap %5.0f MB | pressure %d",
                 Date().timeIntervalSince(start), tag, fr, resident(twin.processIdentifier), v.availMB, sysctlInt("kern.memorystatus_level"), v.compressedMB, v.swapMB, sysctlInt("kern.memorystatus_vm_pressure_level")))
}

guard sysctlInt("kern.memorystatus_vm_pressure_level") == 1 else { print("pressure not normal; skipped"); exit(0) }
let victim = ["--mb", "1024", "--data", "compressible", "--touch-every", "2"]
let frozen = [spawn(victim), spawn(victim)]
let twin = spawn(victim)
usleep(500_000)
line("start", frozen, twin)
for f in frozen { kill(f.processIdentifier, SIGSTOP) }
let swap0 = vm().swapMB
// 1. No pressure: does freezing alone free anything?
for i in 1...6 { sleep(10); line("idle+\(i * 10)s", frozen, twin) }
// 2. Bounded pressure ramp: 256 MB of incompressible memory every 2 s.
var induced = 3072.0
var stop: String?
while induced + 256 <= ram * capPercent / 100 {
    _ = spawn(["--mb", "256", "--data", "random"])
    induced += 256
    sleep(2)
    line("+\(Int(induced))MB", frozen, twin)
    if sysctlInt("kern.memorystatus_vm_pressure_level") >= 4 { stop = "critical"; break }
    if vm().swapMB - swap0 > 768 { stop = "swap limit"; break }
    if frozen.map({ resident($0.processIdentifier) }).reduce(0, +) < 100 { stop = "frozen fixtures compressed"; break }
}
for i in 1...3 { sleep(5); line("hold+\(i * 5)s", frozen, twin) }
print("stopped: \(stop ?? "cap reached")")
