// Phase 0 spike: what happens to a GUI app under SIGSTOP, what window
// information is visible without Screen Recording, and how fast the
// activation notification arrives (including for a frozen app).
// The only app signalled or activated is an ic-hog --gui instance spawned here.
//
// Build: swiftc -O -o gui_spike spikes/gui_spike.swift
// Run:   ./gui_spike <path-to-ic-hog>
import AppKit
import ApplicationServices

_ = NSApplication.shared
func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
func ms(_ ns: UInt64) -> Double { Double(ns) / 1e6 }

// Wrap ic-hog in a minimal .app bundle so LaunchServices (`open -a`) can
// activate it the same way a Dock click or Cmd+Tab would.
let bundle = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("ic-hog.app")
try? FileManager.default.removeItem(at: bundle)
try! FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
try! FileManager.default.copyItem(atPath: CommandLine.arguments[1], toPath: bundle.appendingPathComponent("Contents/MacOS/ic-hog").path)
let plist: [String: Any] = ["CFBundleIdentifier": "io.github.iclean.hog", "CFBundleExecutable": "ic-hog",
                            "CFBundleName": "ic-hog", "CFBundlePackageType": "APPL"]
(plist as NSDictionary).write(to: bundle.appendingPathComponent("Contents/Info.plist"), atomically: true)

let hog = Process()
hog.executableURL = bundle.appendingPathComponent("Contents/MacOS/ic-hog")
hog.arguments = ["--gui", "--mb", "32", "--heartbeat-ms", "1"]
let hogOut = Pipe()
hog.standardOutput = hogOut
var hogLines: [String] = []
let hogLock = NSLock()
var hogBuffer = ""
hogOut.fileHandleForReading.readabilityHandler = { h in
    hogBuffer += String(data: h.availableData, encoding: .utf8) ?? ""
    let parts = hogBuffer.components(separatedBy: "\n")
    hogBuffer = parts.last!
    hogLock.lock(); hogLines += parts.dropLast(); hogLock.unlock()
}
try! hog.run()
let pid = hog.processIdentifier
atexit { kill(pid, SIGCONT); kill(pid, SIGKILL) }
signal(SIGINT) { _ in exit(1) }

func lastStamp(_ prefix: String, after t: UInt64) -> UInt64? {
    hogLock.lock(); defer { hogLock.unlock() }
    return hogLines.compactMap { l -> UInt64? in
        guard l.hasPrefix(prefix + " "), let v = UInt64(l.dropFirst(prefix.count + 1)), v > t else { return nil }
        return v
    }.first
}

func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
func app() -> NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
func windows() -> [[String: Any]] {
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
}
func state() -> String {
    let p = Process(); let out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-o", "stat=", "-p", "\(pid)"]
    p.standardOutput = out; try? p.run(); p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
}

for _ in 0..<50 where app() == nil || windows().isEmpty { pump(0.1) }
pump(0.5)

print("== permissions of this process (preflight only, never prompts)")
print("  Screen Recording: \(CGPreflightScreenCaptureAccess())  Input Monitoring: \(CGPreflightListenEventAccess())  Accessibility: \(AXIsProcessTrusted())")

print("== CGWindowListCopyWindowInfo for the hog window")
for w in windows() where (w[kCGWindowLayer as String] as? Int) == 0 {
    print("  keys: \(w.keys.sorted().joined(separator: ", "))")
    print("  owner name: \(w[kCGWindowOwnerName as String] ?? "nil"), window name: \(w[kCGWindowName as String] ?? "nil (hidden without Screen Recording)")")
    print("  onscreen: \(w[kCGWindowIsOnscreen as String] ?? "nil"), bounds: \(w[kCGWindowBounds as String] ?? "nil")")
}

print("== SIGSTOP a GUI app")
print("  before: ps=\(state()) running-app listed=\(app() != nil) windows=\(windows().count)")
kill(pid, SIGSTOP)
pump(3)
let onscreen = windows().filter { ($0[kCGWindowIsOnscreen as String] as? Bool) == true }.count
print("  after 3 s stopped: ps=\(state()) running-app listed=\(app() != nil) terminated=\(app()?.isTerminated ?? true) windows=\(windows().count) onscreen=\(onscreen)")
kill(pid, SIGCONT)
pump(0.5)
print("  after SIGCONT: ps=\(state())")

print("== activation notification latency")
var activatedAt: UInt64 = 0
var activatedPid: pid_t = 0
let center = NSWorkspace.shared.notificationCenter
let token = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { n in
    let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    activatedPid = a?.processIdentifier ?? 0
    activatedAt = now()
    // Thaw first, before any other work, exactly as the daemon will.
    if activatedPid == pid { kill(pid, SIGCONT) }
}
let previous = NSWorkspace.shared.frontmostApplication
func restoreFocus() {
    if let url = previous?.bundleURL {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", url.path]
        try? p.run(); p.waitUntilExit()
    }
    pump(0.4)
}
func waitActivation(_ deadline: Double = 3) -> Bool {
    let end = Date().addingTimeInterval(deadline)
    while activatedPid != pid && Date() < end { pump(0.0005) }
    return activatedPid == pid
}

var selfActivation: [Double] = []
for _ in 0..<5 {
    activatedPid = 0
    let t = now()
    kill(pid, SIGUSR1)
    if waitActivation(), let a = lastStamp("activate", after: t) { selfActivation.append(ms(activatedAt - a)) }
    print("    frontmost after self-activate: \(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)")
    restoreFocus()
}
var openFrozen: [(notify: Double, heartbeat: Double)] = []
var openRunning: [Double] = []
for frozen in [false, true] {
    for _ in 0..<5 {
        activatedPid = 0
        if frozen { kill(pid, SIGSTOP); pump(0.3) }
        let t = now()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", bundle.path]
        try? p.run()
        if waitActivation(5) {
            if frozen {
                pump(0.05)
                let hb = lastStamp("hb", after: activatedAt).map { ms($0 - activatedAt) } ?? -1
                openFrozen.append((ms(activatedAt - t), hb))
            } else {
                openRunning.append(ms(activatedAt - t))
            }
        } else if frozen {
            openFrozen.append((-1, -1))
        }
        p.waitUntilExit()
        kill(pid, SIGCONT)
        restoreFocus()
    }
}
func summary(_ xs: [Double]) -> String {
    guard !xs.isEmpty else { return "not observed" }
    let s = xs.sorted()
    return String(format: "n=%d min %.1f ms, median %.1f ms, max %.1f ms", s.count, s[0], s[s.count / 2], s.last!)
}
print("  app self-activation -> didActivate notification in observer: \(summary(selfActivation))")
print("  `open -a` on running app -> didActivate: \(summary(openRunning))")
print("  `open -a` on FROZEN app -> didActivate: \(summary(openFrozen.map(\.notify).filter { $0 >= 0 }))  (\(openFrozen.filter { $0.notify < 0 }.count) of \(openFrozen.count) not delivered)")
print("  frozen app: didActivate -> SIGCONT -> first heartbeat: \(summary(openFrozen.map(\.heartbeat).filter { $0 >= 0 }))")
center.removeObserver(token)
