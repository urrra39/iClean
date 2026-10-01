// Phase P spike (a, h): hide -> SIGSTOP -> SIGCONT -> unhide on GUI fixtures this
// program starts itself, and whether window bounds, order and the frontmost app come
// back. Also checks that NSWorkspace power-off, sleep and session notifications can
// be subscribed to.
//
// Build: swiftc -O -o stash_spike spikes/stash_spike.swift
// Run:   ./stash_spike <path-to-ic-ui-probe>
import AppKit

_ = NSApplication.shared
func pump(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let probe = CommandLine.arguments[1]
// Wrap the probe in .app bundles so LaunchServices can activate them like real apps.
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stash-spike-\(getpid())")
var apps: [NSRunningApplication] = []
let frames = ["120,140,420,260", "620,180,380,240", "300,420,360,220"]
for (i, f) in frames.enumerated() {
    let b = tmp.appendingPathComponent("Probe\(i).app/Contents/MacOS")
    try! FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    try! FileManager.default.copyItem(atPath: probe, toPath: b.appendingPathComponent("ic-ui-probe").path)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "io.github.urrra39.iclear.lab.probe\(i)", "CFBundleExecutable": "ic-ui-probe",
        "CFBundleName": "Probe\(i)", "CFBundlePackageType": "APPL",
    ]
    (plist as NSDictionary).write(to: tmp.appendingPathComponent("Probe\(i).app/Contents/Info.plist"), atomically: true)
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.arguments = ["--frame", f, "--title", "probe\(i)"]
    cfg.createsNewApplicationInstance = true
    cfg.activates = i == 2
    var got: NSRunningApplication?
    NSWorkspace.shared.openApplication(at: tmp.appendingPathComponent("Probe\(i).app"), configuration: cfg) { a, _ in got = a }
    for _ in 0..<100 where got == nil { pump(0.05) }
    apps.append(got!)
}
atexit {
    for a in apps {
        kill(a.processIdentifier, SIGCONT)
        kill(a.processIdentifier, SIGKILL)
    }
    try? FileManager.default.removeItem(at: tmp)
}
pump(1.5)

func windows() -> [(pid: Int32, rect: CGRect, onscreen: Bool)] {
    let pids = Set(apps.map(\.processIdentifier))
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
            (w[kCGWindowLayer as String] as? Int) == 0,
            let b = w[kCGWindowBounds as String] as? [String: CGFloat],
            let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.width > 100, r.height > 50
        else { return nil }
        return (pid, r, (w[kCGWindowIsOnscreen as String] as? Bool) ?? false)
    }
}
func onscreenOrder() -> [Int32] {
    let pids = Set(apps.map(\.processIdentifier))
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid), (w[kCGWindowLayer as String] as? Int) == 0 else {
            return nil
        }
        return pid
    }
}

let before = windows()
let orderBefore = onscreenOrder()
let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
print(
    "windows before: \(before.map { "\($0.pid) \(Int($0.rect.origin.x)),\(Int($0.rect.origin.y)) \(Int($0.rect.width))x\(Int($0.rect.height)) on=\($0.onscreen)" })"
)
print("front-to-back before: \(orderBefore), frontmost probe? \(apps.map(\.processIdentifier).contains(frontBefore ?? 0))")

// (a) hide each app while running, wait for its windows to leave the screen.
var hideMs: [Double] = []
for a in apps {
    let t = Date()
    let ok = a.hide()
    var waited = 0.0
    while windows().contains(where: { $0.pid == a.processIdentifier && $0.onscreen }) && waited < 3 {
        pump(0.01)
        waited += 0.01
    }
    hideMs.append(Date().timeIntervalSince(t) * 1000)
    print(
        "hide() returned \(ok); hidden=\(a.isHidden); on-screen windows left: \(windows().filter { $0.pid == a.processIdentifier && $0.onscreen }.count)"
    )
}
print(String(format: "hide to off-screen: %@ ms", hideMs.map { String(format: "%.0f", $0) }.joined(separator: ", ")))
for a in apps { kill(a.processIdentifier, SIGSTOP) }
pump(3)
print("frozen 3 s; windows still listed (off-screen): \(windows().count)")
for a in apps { kill(a.processIdentifier, SIGCONT) }
// Unhide front to back: each unhidden app is placed behind the ones already shown.
for pid in orderBefore {
    let a = apps.first { $0.processIdentifier == pid }!
    let ok = a.unhide()
    print("unhide() \(pid) returned \(ok)")
    pump(0.3)
}
// Restore the frontmost app through LaunchServices (activate() is refused from background processes).
if let fb = apps.first(where: { $0.processIdentifier == frontBefore }), let url = fb.bundleURL {
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
}
pump(1.5)
let after = windows()
var worst = 0.0
for w in before {
    if let a = after.first(where: { $0.pid == w.pid }) {
        let d = max(
            abs(a.rect.minX - w.rect.minX), abs(a.rect.minY - w.rect.minY), abs(a.rect.width - w.rect.width),
            abs(a.rect.height - w.rect.height))
        worst = max(worst, Double(d))
    }
}
print(
    "windows after: \(after.map { "\($0.pid) \(Int($0.rect.origin.x)),\(Int($0.rect.origin.y)) \(Int($0.rect.width))x\(Int($0.rect.height)) on=\($0.onscreen)" })"
)
print(String(format: "max bounds difference: %.1f points", worst))
print(
    "front-to-back after: \(onscreenOrder()) (before \(orderBefore)); frontmost restored: \(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore)"
)

// (h) notification registration
let nc = NSWorkspace.shared.notificationCenter
var tokens: [NSObjectProtocol] = []
for n in [
    NSWorkspace.willPowerOffNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
    NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
] {
    tokens.append(nc.addObserver(forName: n, object: nil, queue: .main) { _ in print("received \(n.rawValue)") })
}
print(
    "registered \(tokens.count) workspace notification observers (delivery needs a real power-off/sleep/user switch; see docs/MANUAL_TESTS.md)"
)
