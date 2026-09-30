// icleand: the iClean daemon (a per-user LaunchAgent; never runs as root).
import AppKit
import Foundation
import ICSystem

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--watchdog", let parent = pid_t(args[2]) {
    Watchdog.run(parent: parent, paths: Paths())
}
if getuid() == 0 {
    FileHandle.standardError.write(Data("icleand must not run as root.\n".utf8))
    exit(1)
}

// Workspace notifications (activation, wake) are delivered to an NSApplication run loop.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
do {
    let daemon = try Daemon()
    let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: args[0])
    try daemon.start(watchdogExecutable: exe)
    withExtendedLifetime(daemon) { app.run() }
} catch {
    FileHandle.standardError.write(Data("icleand: \(error)\n".utf8))
    exit(1)
}
