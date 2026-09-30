// iclean: command-line interface to the iClean daemon.
import Foundation
import ICCore
import ICSystem

let paths = Paths()
var args = Array(CommandLine.arguments.dropFirst())
let json = args.contains("--json")
args.removeAll { $0 == "--json" }

func out(_ s: String) { print(s) }
func fail(_ s: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((s + "\n").utf8))
    exit(code)
}

func daemon(_ req: Request) -> Response? { IPC.send(req, path: paths.socket.path) }

/// Sends a request and prints the answer; exits non-zero when the daemon refuses.
func ask(_ cmd: String, app: String? = nil, value: String? = nil) {
    guard let r = daemon(Request(cmd, app: app, value: value, json: json)) else {
        fail("icleand is not running. Start it with `iclean install`, or run `iclean doctor`.")
    }
    out(json ? (r.data ?? r.text) : r.text)
    if !r.ok { exit(1) }
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

/// "7d", "12h", "30m" -> seconds.
func duration(_ s: String) -> Double? {
    guard let n = Double(s.dropLast()) else { return Double(s) }
    switch s.last {
    case "d": return n * 86400
    case "h": return n * 3600
    case "m": return n * 60
    default: return nil
    }
}

let installer = Installer(paths: paths, daemonPath: (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    .resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("icleand").path)

let usage = """
iClean pauses idle background apps under memory pressure and resumes them the moment you
switch back. It never deletes files.

Usage: iclean <command> [options]

  status [--json]                  what iClean is doing now
  why [--json]                     why is my Mac slow right now?
  explain <app>                    why an app was or was not frozen
  thaw [<app> | --all]             resume frozen apps (works even if the daemon is dead)
  freeze <app>                     freeze one app now (safety checks still apply)
  undo                             thaw the last round of freezes
  mode [observe | active]          show or change the mode
  profile [work | batterySaver | presentation | dev | auto]
  stats [--days N] [--json]        digest of what iClean measured
  advise                           RAM right-sizing estimate (needs 7 days of history)
  quarantine [release <app>]       apps that misbehaved after a thaw
  habits [show | reset | export]   local app-switch statistics
  workspace [<name> freeze | thaw]
  simulate [--config FILE] [--since 7d]    replay recorded traces with another config
  trace export [--anonymize] [--since 7d] [--out FILE]
  config [path | show | validate [FILE] | allow <app> | deny <app> | import FILE | export]
  doctor [--report]                what works on this Mac
  install | uninstall [--purge]    manage the per-user LaunchAgent
  bench [--quick]                  run the benchmark scenarios (spawns test processes only)
  completions [zsh | bash | fish]
  version
"""

guard let cmd = args.first else { out(usage); exit(0) }
let rest = Array(args.dropFirst())

switch cmd {
case "help", "-h", "--help":
    out(usage)

case "version", "--version":
    out("iclean \(icleanVersion)")

case "status":
    if let r = daemon(Request("status", json: json)) {
        out(json ? (r.data ?? r.text) : r.text)
    } else {
        let j = JournalStore(url: paths.journal).read()
        out("icleand is not running." + (j.entries.isEmpty ? "" : " The journal lists \(j.entries.count) frozen process(es): run `iclean thaw --all`."))
        exit(3)
    }

case "why":
    if let r = daemon(Request("why", json: json)) {
        out(json ? (r.data ?? r.text) : r.text)
    } else {
        // No daemon: take two quick readings ourselves (no history, so no trends).
        let c = AppCollector()
        _ = c.collect()
        Thread.sleep(forTimeInterval: 1)
        let now = Date().timeIntervalSince1970
        let r = c.collect(now: now)
        let d = Why.diagnose(samples: [SystemSampler.sample(now: now)], apps: r.apps, runaway: [],
                             forecast: Forecast(armed: false, stable: true), idleMinutes: { _ in 0 })
        out("(icleand is not running: one snapshot, no history)\n" + d.text)
    }

case "explain":
    guard let app = rest.first else { fail("usage: iclean explain <app>") }
    ask("explain", app: app)

case "thaw":
    let all = rest.isEmpty || rest.contains("--all")
    if let r = daemon(Request("thaw", app: all ? "all" : rest.first)) {
        out(r.text)
    } else if all {
        let r = Signals.recover(journal: JournalStore(url: paths.journal))
        out("icleand is not running; thawed \(r.thawed) process(es) from the journal" + (r.stale > 0 ? ", \(r.stale) already gone" : "")
            + (r.corrupt ? " (journal was corrupt: resumed every stopped app process)" : "") + ".")
    } else {
        fail("icleand is not running. `iclean thaw --all` works without it.")
    }

case "freeze":
    guard let app = rest.first else { fail("usage: iclean freeze <app>") }
    ask("freeze", app: app)

case "undo":
    ask("undo")

case "mode":
    ask("mode", value: rest.first)

case "profile":
    ask("profile", value: rest.first)

case "stats":
    let days = option("--days").flatMap(Int.init) ?? (rest.contains("--week") ? 7 : 1)
    ask("stats", value: "\(days)")

case "advise":
    ask("advise")

case "quarantine":
    if rest.first == "release", rest.count > 1 { ask("quarantine", app: rest[1]) } else { ask("quarantine") }

case "habits":
    switch rest.first ?? "show" {
    case "reset": ask("habits", value: "reset")
    case "show", "export": ask("habits")
    default: fail("usage: iclean habits [show | reset | export]")
    }

case "workspace":
    if rest.count >= 2 { ask("workspace", app: rest[0], value: rest[1]) } else { ask("workspace") }

case "simulate":
    var config = Config()
    if let f = option("--config") {
        do { config = try Config.load(json: Data(contentsOf: URL(fileURLWithPath: f))).0 } catch { fail("\(f): \(error)") }
    } else if let data = try? Data(contentsOf: paths.config), let c = try? Config.load(json: data).0 {
        config = c
    }
    config.mode = .active  // simulate what Active mode would have done
    let since = Date().timeIntervalSince1970 - (option("--since").flatMap(duration) ?? 7 * 86400)
    let (recs, skipped) = TraceWriter.read(dir: paths.traces, since: since)
    guard !recs.isEmpty else { fail("No traces recorded since then (see \(paths.traces.path)).") }
    let r = Simulator.run(recs, config: config, hardware: SystemSampler.hardware(), skipped: skipped)
    if json {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        out(String(decoding: try! e.encode(r), as: UTF8.self))
    } else {
        out(r.text)
    }

case "trace":
    guard rest.first == "export" else { fail("usage: iclean trace export [--anonymize] [--since 7d] [--out FILE]") }
    let since = Date().timeIntervalSince1970 - (option("--since").flatMap(duration) ?? 7 * 86400)
    var (recs, _) = TraceWriter.read(dir: paths.traces, since: since)
    if rest.contains("--anonymize") {
        let salt = UUID().uuidString
        recs = recs.map { Trace.anonymize($0, salt: salt) }
    }
    let data = recs.map(Trace.encode).reduce(Data(), +)
    if let f = option("--out") {
        do { try data.write(to: URL(fileURLWithPath: f)) } catch { fail("\(f): \(error)") }
        out("Wrote \(recs.count) records to \(f).")
    } else {
        FileHandle.standardOutput.write(data)
    }

case "config":
    switch rest.first ?? "show" {
    case "path":
        out(paths.config.path)
    case "show", "export":
        let data = (try? Data(contentsOf: paths.config)) ?? Config().encoded()
        out(String(decoding: data, as: UTF8.self))
    case "validate":
        let url = rest.count > 1 ? URL(fileURLWithPath: rest[1]) : paths.config
        do {
            let (_, warnings) = try Config.load(json: Data(contentsOf: url))
            out("valid" + (warnings.isEmpty ? "" : "\n" + warnings.map(\.description).joined(separator: "\n")))
        } catch {
            fail("\(error)")
        }
    case "allow", "deny":
        guard rest.count > 1 else { fail("usage: iclean config \(rest[0]) <bundle id or app name>") }
        ask(rest[0], app: rest[1])
    case "import":
        // Rule packs: only rule keys are taken, and the result is validated before saving.
        guard rest.count > 1, let data = try? Data(contentsOf: URL(fileURLWithPath: rest[1])),
              let pack = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { fail("usage: iclean config import FILE.json") }
        let ruleKeys: Set<String> = ["allow", "deny", "tiers", "wakeWindows", "workspaces"]
        let unknown = Set(pack.keys).subtracting(ruleKeys)
        guard unknown.isEmpty else { fail("A rule pack may only contain \(ruleKeys.sorted()); found \(unknown.sorted()).") }
        var current = (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.config))) as? [String: Any] ?? [:]
        for (k, v) in pack {
            if let list = v as? [String] { current[k] = Array(Set((current[k] as? [String] ?? []) + list)).sorted() }
            else if let map = v as? [String: Any] { current[k] = (current[k] as? [String: Any] ?? [:]).merging(map) { _, new in new } }
        }
        do {
            let merged = try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted, .sortedKeys])
            let (_, warnings) = try Config.load(json: merged)
            try paths.ensure()
            try Files.atomicWrite(merged, to: paths.config)
            out("Imported \(pack.keys.sorted().joined(separator: ", ")).\(warnings.isEmpty ? "" : "\n" + warnings.map(\.description).joined(separator: "\n"))")
            _ = daemon(Request("reload"))
        } catch {
            fail("Rule pack rejected: \(error)")
        }
    default:
        fail("usage: iclean config [path | show | validate [FILE] | allow <app> | deny <app> | import FILE | export]")
    }

case "doctor":
    let r = Doctor.run(paths: paths, installer: installer)
    out(rest.contains("--report") ? Doctor.issueReport(r) : Doctor.text(r))

case "install":
    do { out(try installer.install()) } catch { fail("install failed: \(error)") }

case "uninstall":
    out(installer.uninstall(purge: rest.contains("--purge")))

case "bench":
    let hog = installer.daemonPath.replacingOccurrences(of: "/icleand", with: "/ic-hog")
    guard FileManager.default.isExecutableFile(atPath: hog) else { fail("ic-hog not found next to iclean; benchmarks need it.") }
    let result = Bench.run(hogPath: hog, quick: rest.contains("--quick"), log: { out($0) })
    out(json ? result.json : result.markdown)

case "completions":
    out(Completions.script(for: rest.first ?? "zsh"))

default:
    fail("Unknown command '\(cmd)'. Run `iclean help`.")
}
