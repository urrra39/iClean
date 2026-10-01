// iClear Lab launcher: runs the lab harness (../bin/ic-lab next to the app) as a child
// process. Permissions granted to this small, rarely rebuilt app (Accessibility,
// microphone) then cover the harness, which is rebuilt often.
import Foundation

let root = Bundle.main.bundleURL.deletingLastPathComponent()
let results = root.appendingPathComponent("results")
try? FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
let logURL = results.appendingPathComponent("console.log")
if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
let log = FileHandle(forWritingAtPath: logURL.path)
_ = try? log?.seekToEnd()

let child = Process()
child.executableURL = root.appendingPathComponent("bin/ic-lab")
child.arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
child.standardOutput = log
child.standardError = log
for s in [SIGINT, SIGTERM, SIGHUP] {
    signal(s, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: s, queue: .global())
    src.setEventHandler { child.terminate() }
    src.resume()
    _ = Unmanaged.passRetained(src)
}
do {
    try child.run()
} catch {
    log?.write(Data("could not start \(child.executableURL!.path): \(error)\n".utf8))
    exit(1)
}
child.waitUntilExit()
exit(child.terminationStatus)
