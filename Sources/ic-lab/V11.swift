import AppKit
import Foundation
import ICCore
import ICSystem

/// Stage 4 (v1.1) phases: Auto-Context Stash (X2-X6) and the leak trend (L1-L4, and the
/// L5 retrospective on a recorded Observe trace). Only lab fixtures are ever signalled.
extension Lab {
    // MARK: Auto-Context

    /// X2 wrong-app stashes and X3 enter-to-usable latency over `switches` automatic
    /// switches between three contexts; X4 false triggers; X5 undo; X6 kill -9 mid-switch.
    func contextLab(switches: Int, falseEvents: Int, undos: Int, crashes: Int, tools: URL) {
        struct Row: Codable {
            var switches = 0, switchOK = 0, wrongApps = 0
            var latencyMs: [Double] = []
            var falseEvents: [String: Int] = [:]
            var falseSwitches: [String: Int] = [:]
            var undos = 0, undoOK = 0
            var crashes = 0, crashOK = 0, crashMidSwitch = 0
            var crashMs: [Double] = []
        }
        var r = Row()
        let dir = out.appendingPathComponent("ctx-probes-\(getpid())")
        let probe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
            .appendingPathComponent("ic-ui-probe").path
        let names = ["CtxA1", "CtxA2", "CtxB1", "CtxC1", "CtxShared"]
        let frames = ["120,140,320,200", "470,160,320,200", "820,180,320,200", "170,420,320,200", "520,440,320,200"]
        let apps: [AppFixture] = names.enumerated().compactMap { i, n in
            guard let g = try? GUIFixture(probe: probe, dir: dir, name: n, frame: frames[i]) else { return nil }
            return AppFixture(kind: "probe", name: n, app: g.app, dataDir: dir.appendingPathComponent(n), docs: [])
        }
        let saved = fixtures
        regLock.lock()
        fixtures = apps
        everStarted += apps
        regLock.unlock()
        defer {
            for a in apps { a.kill() }
            regLock.lock()
            fixtures = saved
            regLock.unlock()
        }
        guard apps.count == names.count else { return log("context: probe apps did not start") }
        let app = Dictionary(uniqueKeysWithValues: apps.map { ($0.name, $0) })
        let groups = ["a": ["CtxA1", "CtxA2", "CtxShared"], "b": ["CtxB1", "CtxShared"], "c": ["CtxC1", "CtxShared"]]
        let root = "/opt/iclear-lab"
        func id(_ n: String) -> String { "io.github.urrra39.iclear.fixture.\(n)" }
        func others(_ c: String) -> [String] { groups.keys.filter { $0 != c }.sorted() }
        func paused(_ f: AppFixture) -> Bool { f.stopped() && f.isHidden }
        func running(_ f: AppFixture) -> Bool { !f.stopped() && !f.isHidden }
        func isFront(_ n: String) -> Bool { NSRunningApplication(processIdentifier: app[n]!.pid)?.isActive == true }

        let paths = Paths(environment: ["ICLEAR_HOME": labHome("ctx").path, "ICLEAR_INSTANCE": "lab"])
        var d: Process?
        /// A fresh daemon with this cooldown (stopping the old one resumes what it paused).
        func restart(cooldown: Double) {
            if let p = d, p.isRunning {
                p.terminate()
                p.waitUntilExit()
            }
            var c = Config()
            c.mode = .active
            c.contexts = groups.keys.sorted().map { k in ContextRule(name: k, path: "\(root)/\(k)", apps: groups[k]!.map(id), auto: true) }
            c.context.dwellSeconds = 2
            c.context.cooldownMinutes = cooldown
            try? paths.ensure()
            try? c.encoded().write(to: paths.config)
            d = startDaemon(paths, tools: tools)
        }
        func ask(_ sub: String, _ args: [String: Any] = [:]) -> Response? {
            let v = String(decoding: (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8), as: UTF8.self)
            return IPC.send(Request("context", app: sub, value: v), path: paths.socket.path, timeout: 30)
        }
        func enter(_ p: String) { _ = ask("enter", ["path": p, "source": "lab"]) }
        func current() -> String? {
            guard let line = ask("status")?.text.split(separator: "\n").first, line.hasPrefix("Current context: ") else { return nil }
            let name = String(line.dropFirst("Current context: ".count).split(separator: " ").first ?? "")
            return name == "none" ? nil : name
        }
        func switchCount() -> Int {
            ActionLog.read(paths: paths, last: 1_000_000).filter { $0.action.message?.hasPrefix("Context: switched") == true }.count
        }
        func until(_ seconds: Double, _ cond: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if cond() { return true }
                usleep(20_000)
            }
            return cond()
        }
        /// Works in context `c`: one of its own apps comes to the front.
        func work(in c: String, leavingFor to: String, _ i: Int) -> String? {
            let own = groups[c]!.filter { !groups[to]!.contains($0) }
            let n = own[i % own.count]
            Lab.bringToFront(app[n]!)
            usleep(300_000)
            return isFront(n) ? n : nil
        }

        restart(cooldown: 0)
        _ = ask("switch", ["name": "a"])
        var cur = "a"
        var frontWhenLeft: [String: String] = [:]

        // X2, X3: automatic switches at the end of the dwell time.
        for i in 0..<switches {
            powerGate()
            let to = others(cur)[Int.random(in: 0..<2)]
            frontWhenLeft[cur] = work(in: cur, leavingFor: to, i)
            let leaving = Set(groups[cur]!).subtracting(groups[to]!)
            let t0 = Date()
            enter("\(root)/\(to)/src")
            let due = t0.addingTimeInterval(2)
            let done = until(12) {
                groups[to]!.allSatisfy { running(app[$0]!) } && leaving.allSatisfy { paused(app[$0]!) }
                    && (frontWhenLeft[to].map(isFront) ?? true)
            }
            let latency = Date().timeIntervalSince(due) * 1000
            let journal = JournalStore(url: paths.journal).read()
            let stashed = Set(journal.stashes.first { $0.name == "context:\(cur)" }?.apps.filter { !$0.popped }.map(\.appID) ?? [])
            let wrong = stashed.subtracting(leaving.map(id)).count + groups[to]!.filter { app[$0]!.stopped() || app[$0]!.isHidden }.count
            r.wrongApps += wrong
            r.switches += 1
            let now = current()
            if done && wrong == 0 && now == to {
                r.switchOK += 1
                r.latencyMs.append(latency)
            } else {
                log("context switch \(i) \(cur) → \(to): done \(done), wrong apps \(wrong), current \(now ?? "none")")
            }
            cur = now ?? to
            if i % 20 == 0 { log("context switch \(i + 1)/\(switches)") }
        }

        // X4: events that must not switch.
        func mustNotSwitch(_ kind: String, wait: Double = 3.5, _ body: () -> Void) {
            let before = switchCount()
            body()
            usleep(UInt32(wait * 1_000_000))
            r.falseEvents[kind, default: 0] += 1
            let n = switchCount() - before
            if n > 0 || current() != cur {
                r.falseSwitches[kind, default: 0] += max(n, 1)
                log("false trigger (\(kind)): \(n) switch(es), current \(current() ?? "none")")
                _ = ask("switch", ["name": cur])
            }
        }
        let per = max(1, falseEvents / 5)
        for i in 0..<per {
            powerGate()
            mustNotSwitch("move inside the context") { enter("\(root)/\(cur)/src/deep/\(i)") }
            mustNotSwitch("cd /tmp") { enter("/tmp/iclear-lab-\(i)") }
            mustNotSwitch("cd ~") { enter(paths.home.path) }
            mustNotSwitch("left and re-entered within the dwell time") {
                enter("\(root)/\(others(cur)[i % 2])")
                usleep(800_000)
                enter("\(root)/\(cur)")
            }
        }
        restart(cooldown: 0.25)
        for i in 0..<per {
            powerGate()
            // A real switch starts the cooldown; another context asked for inside it must wait.
            let to = others(cur)[i % 2]
            enter("\(root)/\(to)")
            guard until(12, { current() == to }) else {
                log("cooldown block \(i): the real switch to \(to) did not happen")
                continue
            }
            let switched = Date()
            cur = to
            mustNotSwitch("inside the cooldown", wait: 5) { enter("\(root)/\(others(cur)[i % 2])") }
            enter("\(root)/\(cur)")
            let left = 15.5 - Date().timeIntervalSince(switched)
            if left > 0 { usleep(UInt32(left * 1_000_000)) }
        }

        // X5: undo restores paused/running, hidden/shown and the frontmost app.
        restart(cooldown: 0)
        _ = ask("switch", ["name": cur])
        func snapshot() -> [String] { names.map { "\($0):\(app[$0]!.stopped()):\(app[$0]!.isHidden):\(isFront($0))" } }
        for i in 0..<undos {
            powerGate()
            let to = others(cur)[i % 2]
            _ = work(in: cur, leavingFor: to, i)
            let before = snapshot()
            enter("\(root)/\(to)")
            guard until(12, { current() == to && groups[to]!.allSatisfy { running(app[$0]!) } }) else {
                log("undo \(i): the switch to \(to) did not happen")
                r.undos += 1
                continue
            }
            usleep(500_000)
            let u = ask("undo")
            let ok = u?.ok == true && until(5) { snapshot() == before }
            r.undos += 1
            if ok { r.undoOK += 1 } else { log("undo \(i): \(u?.text ?? "no answer"); before \(before), after \(snapshot())") }
            cur = current() ?? cur
        }

        // X6: kill -9 of the daemon during a switch.
        for i in 0..<crashes {
            powerGate()
            if d?.isRunning != true { restart(cooldown: 0) }
            _ = ask("switch", ["name": cur])
            usleep(500_000)
            let to = others(cur)[i % 2]
            _ = work(in: cur, leavingFor: to, i)
            let t0 = Date()
            enter("\(root)/\(to)")
            // Spread the kill over the switch: from the end of the dwell time to 1.5 s after it.
            usleep(UInt32((2.0 + Double(i % 16) * 0.1) * 1_000_000 - Date().timeIntervalSince(t0) * 1_000_000))
            let mid = apps.contains { $0.stopped() || $0.isHidden }
            if let p = d {
                kill(p.processIdentifier, SIGKILL)
                p.waitUntilExit()
            }
            let t = Date()
            let back = until(5) { apps.allSatisfy(running) }
            let took = Date().timeIntervalSince(t)
            r.crashes += 1
            if mid { r.crashMidSwitch += 1 }
            r.crashMs.append(took * 1000)
            if back && took <= 2 { r.crashOK += 1 } else { log("crash \(i): all running and shown \(back) after \(took) s") }
            for a in apps {
                for p in a.tree() { _ = Signals.send(SIGCONT, to: p) }
                if a.isHidden { a.app.unhide() }
            }
            restart(cooldown: 0)
            cur = current() ?? cur
        }
        if let p = d, p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        let falseTotal = r.falseSwitches.values.reduce(0, +)
        let md = """
            ## Auto-Context Stash (X2-X6): \(apps.count) lab apps in 3 contexts, one app shared

            | # | Measure | Result |
            |---|---|---|
            | X2 | Apps stashed that were not in the leaving group (or paused in the new one) | \(r.wrongApps) over \(r.switches) switches |
            | X3 | End of dwell time → every app of the new context shown and the front app restored | \(dist(r.latencyMs)); \(r.switchOK)/\(r.switches) switches complete |
            | X4 | Switches from events that must not switch | \(falseTotal) over \(r.falseEvents.values.reduce(0, +)) events (\(r.falseEvents.sorted { $0.key < $1.key }.map { "\($0.key): \(r.falseSwitches[$0.key] ?? 0)/\($0.value)" }.joined(separator: "; "))) |
            | X5 | Undo restores paused/running, hidden/shown and the front app | \(r.undoOK)/\(r.undos) |
            | X6 | kill -9 during a switch: every lab app running and shown within 2.0 s | \(r.crashOK)/\(r.crashes) (\(r.crashMidSwitch) killed while an app was paused or hidden); \(dist(r.crashMs)) |
            """
        save("context", r, md)
    }

    // MARK: Leak trend

    /// One `ic-hog --app` process tree as a regular app with its own bundle ID.
    func leakTree(_ name: String, args: [String], dir: URL) -> AppFixture? {
        let bundle = dir.appendingPathComponent("\(name).app")
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        let hog = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
            .appendingPathComponent("ic-hog").path
        try? FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: hog, toPath: macos.appendingPathComponent("ic-hog").path)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "io.github.urrra39.iclear.fixture.\(name)", "CFBundleExecutable": "ic-hog", "CFBundleName": name,
            "CFBundlePackageType": "APPL",
        ]
        (plist as NSDictionary).write(to: bundle.appendingPathComponent("Contents/Info.plist"), atomically: true)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.arguments = args + ["--app", "--lifeline", "\(getpid())"]
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        cfg.hides = true
        var got: NSRunningApplication?
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: bundle, configuration: cfg) { a, _ in
            got = a
            done.signal()
        }
        guard done.wait(timeout: .now() + 20) == .success, let a = got else { return nil }
        return AppFixture(kind: "leak", name: name, app: a, dataDir: dir, docs: [])
    }

    /// L1-L4 on `growing` trees (50-110 MB/h, with noise; a third with a child process
    /// that grows too) and `flat` non-growing trees (noise, one step, sawtooth caches),
    /// sampled by an isolated Observe-mode daemon as in normal use. Growing trees are
    /// ended once flagged, to bound memory; the run stops early when swap grows by 1 GB
    /// or pressure turns critical.
    func leakLab(growing: Int, flat: Int, hours: Double, tools: URL) {
        struct Tree: Codable {
            var name: String
            var spec: String
            var children: Int
            var trueRate: Double
            var growing: Bool
            var flaggedAfterHours: Double?
            var finding: LeakFinding?
        }
        var trees: [Tree] = []
        for i in 0..<growing {
            let rate = 50 + Double(i % 7) * 10
            let kids = i % 3 == 0 ? 1 : 0
            trees.append(
                Tree(
                    name: "LeakG\(i)", spec: "rate=\(rate),noise=\([5, 15, 30][i % 3])", children: kids, trueRate: rate * Double(1 + kids),
                    growing: true))
        }
        for i in 0..<flat {
            let spec =
                switch i % 3 {
                case 0: "noise=\([10, 25, 40][i % 3 == 0 ? (i / 3) % 3 : 0])"
                case 1: "step=\(0.5 + Double(i % 5) * 0.5):\(150 + (i % 5) * 50),noise=10"
                default: "saw=\(10 + (i % 4) * 10):\(80 + (i % 5) * 40),noise=5"
                }
            trees.append(Tree(name: "LeakF\(i)", spec: spec, children: 0, trueRate: 0, growing: false))
        }
        let dir = out.appendingPathComponent("leak-apps-\(getpid())")
        var running: [String: AppFixture] = [:]
        for t in trees {
            let args = ["--mb", "20", "--profile", t.spec] + (t.children > 0 ? ["--children", "\(t.children)"] : [])
            guard let f = leakTree(t.name, args: args, dir: dir) else {
                log("leak: \(t.name) did not start")
                continue
            }
            running[t.name] = f
            regLock.lock()
            fixtures.append(f)
            everStarted.append(f)
            regLock.unlock()
        }
        let paths = Paths(environment: ["ICLEAR_HOME": labHome("leaks").path, "ICLEAR_INSTANCE": "lab"])
        guard let d = startDaemon(paths, tools: tools) else { return log("leak: daemon did not start") }
        defer {
            d.terminate()
            d.waitUntilExit()
            for f in running.values { f.kill() }
        }
        let start = Date()
        let swap0 = SystemSampler.sample().swapUsedMB
        var stop: String?
        while Date().timeIntervalSince(start) < hours * 3600 && stop == nil {
            powerGate()
            for _ in 0..<30 {
                sleep(10)
                let s = SystemSampler.sample()
                if s.pressure == .critical || s.swapUsedMB - swap0 > Pressure.swapLimitMB {
                    stop = s.pressure == .critical ? "critical pressure" : "swap grew \(Int(s.swapUsedMB - swap0)) MB"
                    break
                }
            }
            let elapsed = Date().timeIntervalSince(start) / 3600
            let found =
                IPC.send(Request("leaks"), path: paths.socket.path, timeout: 30)?.data
                .flatMap { try? JSONDecoder().decode([LeakFinding].self, from: Data($0.utf8)) } ?? []
            for f in found {
                guard let i = trees.firstIndex(where: { "io.github.urrra39.iclear.fixture.\($0.name)" == f.appID }),
                    trees[i].finding == nil
                else { continue }
                trees[i].finding = f
                trees[i].flaggedAfterHours = elapsed
                let t = trees[i]
                log(String(format: "flagged %@ after %.2f h: %.0f MB/h (true %.0f)", t.name, elapsed, f.rateMBPerHour, t.trueRate))
                if trees[i].growing, let a = running.removeValue(forKey: trees[i].name) { a.kill() }
            }
            log(String(format: "leak run %.2f h: %d flagged", elapsed, trees.filter { $0.finding != nil }.count))
        }
        if let stop { log("leak run stopped early: \(stop)") }
        let hoursRun = Date().timeIntervalSince(start) / 3600
        let g = trees.filter(\.growing)
        let ng = trees.filter { !$0.growing }
        let flagged = trees.filter { $0.finding != nil }
        let recall = g.filter { ($0.flaggedAfterHours ?? .infinity) <= 5 }.count
        let truePositives = flagged.filter(\.growing).count
        let falseFlags = ng.filter { $0.finding != nil }.count
        let treeDays = Double(ng.count) * hoursRun / 24
        let rateErr = g.compactMap { t in t.finding.map { abs($0.rateMBPerHour - t.trueRate) / t.trueRate * 100 } }
        let etaErrMin = g.compactMap { t -> Double? in
            guard let f = t.finding else { return nil }
            let trueHours = (f.targetGB * 1024 - f.currentMB) / t.trueRate
            return ((f.reachesAt - Date().timeIntervalSince1970) / 3600 + (hoursRun - (t.flaggedAfterHours ?? hoursRun)) - trueHours) * 60
        }
        let eta =
            etaErrMin.isEmpty
            ? "no samples"
            : String(
                format: "p50 %.0f, p5 %.0f, p95 %.0f (N=%d)", percentileOf(etaErrMin, 0.5), percentileOf(etaErrMin, 0.05),
                percentileOf(etaErrMin, 0.95), etaErrMin.count)
        let md = """
            ## Leak trend (L1-L4): \(g.count) growing and \(ng.count) non-growing ic-hog trees, \(String(format: "%.1f", hoursRun)) h\(stop.map { ", stopped early: \($0)" } ?? "")

            | # | Measure | Result |
            |---|---|---|
            | L1 | Growing trees (≥ 50 MB/h) flagged within 5 h (2 h minimum data + 3 h) | \(recall)/\(g.count) |
            | L2 | Flagged trees that truly grow (≥ 10 MB/h) | \(truePositives)/\(flagged.count) |
            | L3 | Flags on non-growing trees per tree per day | \(falseFlags) over \(String(format: "%.2f", treeDays)) tree-days = \(String(format: "%.3f", treeDays > 0 ? Double(falseFlags) / treeDays : 0)) |
            | L4 | Absolute rate error, % of the true rate | median \(String(format: "%.1f", percentileOf(rateErr, 0.5)))%; p95 \(String(format: "%.1f", percentileOf(rateErr, 0.95)))% (N=\(rateErr.count)) |
            | L4 | ETA error to the next whole GB, minutes (reported minus true) | \(eta) |
            """
        save("leaks", trees, md)
    }

    /// L5: replays a recorded trace (Observe instance) through the same leak-trend code
    /// every 10 minutes of trace time; each app is judged at its first flag: is its
    /// footprint one hour later within ±30% (or ±100 MB) of the predicted value?
    func leakRetro(traceDir: URL) {
        struct Judged: Codable {
            var app: String
            var flaggedAt: Double
            var predictedMB: Double
            var actualMB: Double?
            var pass: Bool?
        }
        let (recs, skipped) = TraceWriter.read(dir: traceDir, since: 0)
        let sorted = recs.sorted { $0.t < $1.t }
        guard let first = sorted.first?.t, let last = sorted.last?.t else { return log("leak retro: no records in \(traceDir.path)") }
        var history = FootprintHistory()
        var series: [String: [(t: Double, mb: Double)]] = [:]
        var firstFlag: [String: (t: Double, f: LeakFinding)] = [:]
        var nextCheck = first
        for rec in sorted {
            switch rec.k {
            case .activate:
                if let a = rec.app { history.noteFront(a, at: rec.t) }
            case .tick:
                guard let tick = rec.tick else { continue }
                history.add(tick.apps, now: rec.t)
                for a in tick.apps where a.isRegularApp { series[a.id, default: []].append((rec.t, a.footprintMB)) }
                if rec.t >= nextCheck {
                    for f in history.findings(now: rec.t, settings: LeakSettings()) where firstFlag[f.appID] == nil {
                        firstFlag[f.appID] = (rec.t, f)
                    }
                    nextCheck = rec.t + 600
                }
            case .action:
                break
            }
        }
        var judged: [Judged] = []
        for (app, flag) in firstFlag.sorted(by: { $0.value.t < $1.value.t }) {
            let predicted = flag.f.currentMB + flag.f.rateMBPerHour
            let target = flag.t + 3600
            let later = series[app]?.filter { abs($0.t - target) <= 300 }.min { abs($0.t - target) < abs($1.t - target) }
            var j = Judged(app: app, flaggedAt: flag.t, predictedMB: predicted)
            if let later {
                j.actualMB = later.mb
                j.pass = abs(later.mb - predicted) <= max(0.3 * predicted, 100)
            }
            judged.append(j)
        }
        let withData = judged.filter { $0.pass != nil }
        let passed = withData.filter { $0.pass == true }.count
        let share = withData.isEmpty ? "" : String(format: " (%.0f%%)", Double(passed) / Double(withData.count) * 100)
        let md = """
            ## Leak trend retrospective (L5) on a recorded Observe trace

            Trace: \(String(format: "%.1f", (last - first) / 3600)) h, \(sorted.count) records (\(skipped) skipped). \
            Apps flagged: \(judged.count); with a footprint 1 h later: \(withData.count); \
            within ±30% (or ±100 MB) of the prediction: \(passed)/\(withData.count)\(share).
            """
        save("leak-retro", judged, md)
    }
}
