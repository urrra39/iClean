// icbrake: the Panic Brake watchdog (a per-user LaunchAgent of its own; never runs as root).
import AppKit
import Foundation
import ICSystem

let args = CommandLine.arguments
let paths = Paths()
if args.count >= 3, args[1] == "--watchdog", let parent = pid_t(args[2]) {
    Watchdog.run(parent: parent, journal: JournalStore(url: paths.brakeJournal))
}
if getuid() == 0 {
    FileHandle.standardError.write(Data("icbrake must not run as root.\n".utf8))
    exit(1)
}

// Activation notifications are delivered to an NSApplication run loop.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let agent = BrakeAgent(paths: paths)
do {
    try agent.start(watchdogExecutable: Bundle.main.executableURL ?? URL(fileURLWithPath: args[0]))
} catch {
    FileHandle.standardError.write(Data("icbrake: \(error)\n".utf8))
    exit(1)
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
    if let a = $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        agent.handleActivation(pid: a.processIdentifier)
    }
}
for s in [SIGTERM, SIGINT, SIGHUP] {
    signal(s, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
    src.setEventHandler {
        agent.shutdown()
        exit(0)
    }
    src.resume()
    _ = Unmanaged.passRetained(src)
}
app.run()
