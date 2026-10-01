// Auto-Context spike: cost of finding the git branch for a directory by reading
// `.git/HEAD` of the nearest repository (the same steps as `Daemon.gitBranch`), so no
// `git` process runs per shell event.
//
//     swiftc -O -o /tmp/branch_spike spikes/branch_spike.swift && /tmp/branch_spike "$PWD/Sources/ICSystem" 10000
import Foundation

func gitBranch(_ path: String) -> String? {
    var dir = URL(fileURLWithPath: path)
    for _ in 0..<40 {
        let git = dir.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: git.path) {
            var head = git.appendingPathComponent("HEAD")
            if let link = try? String(contentsOf: git, encoding: .utf8), link.hasPrefix("gitdir: ") {
                let target = link.dropFirst("gitdir: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                head = URL(fileURLWithPath: target, relativeTo: dir).appendingPathComponent("HEAD")
            }
            let line = (try? String(contentsOf: head, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return line.hasPrefix("ref: refs/heads/") ? String(line.dropFirst("ref: refs/heads/".count)) : nil
        }
        if dir.path == "/" { return nil }
        dir.deleteLastPathComponent()
    }
    return nil
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted()
    return s[min(s.count - 1, Int((p / 100 * Double(s.count - 1)).rounded()))]
}

let args = CommandLine.arguments
let n = args.count > 2 ? Int(args[2]) ?? 10000 : 10000
let dirs = [args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath, "/usr/share/man/man1", "/tmp"]
for d in dirs {
    var t: [Double] = []
    var branch: String?
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        branch = gitBranch(d)
        t.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1000)
    }
    let f = { (x: Double) in String(format: "%.1f µs", x) }
    print("\(d): branch \(branch ?? "none"), N \(n), p50 \(f(percentile(t, 50))), p95 \(f(percentile(t, 95))), max \(f(t.max() ?? 0))")
}
