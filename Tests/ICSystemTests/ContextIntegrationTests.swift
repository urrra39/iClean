import AppKit
import Foundation
import Testing

@testable import ICCore
@testable import ICSystem

/// Auto-Context switches on GUI fixtures (ic-ui-probe apps started by the test).
@Suite(.serialized) struct ContextIntegrationTests {
    let probePath = products.appendingPathComponent("ic-ui-probe").path

    func fixtures(_ names: [String], in paths: Paths) throws -> [GUIFixture] {
        let frames = ["110,140,360,220", "520,170,360,220", "260,420,360,220"]
        return try names.enumerated().map { i, n in try GUIFixture(probe: probePath, dir: paths.home, name: n, frame: frames[i]) }
    }

    func daemon(_ fx: [GUIFixture], _ paths: Paths, mode: Mode = .active, rules: [ContextRule]) throws -> (Daemon, FakeProbe) {
        let probe = FakeProbe()
        probe.apps = fx.map { $0.snapshot() }
        let d = try testDaemon(probe, paths: paths, mode: mode) {
            $0.contexts = rules
            $0.context.dwellSeconds = 0
            $0.context.cooldownMinutes = 0
        }
        d.tick()
        return (d, probe)
    }

    func paused(_ f: GUIFixture) -> Bool { isStopped(f.pid) && f.isHidden }
    func running(_ f: GUIFixture) -> Bool { !isStopped(f.pid) && !f.isHidden }

    /// A switch stashes the leaving group, keeps an app both groups use, and pops the
    /// new group's stash; undo reverses it; the journal ends empty.
    @Test func switchSharedAppAndUndo() throws {
        let paths = tempHome()
        let fx = try fixtures(["CtxA", "CtxB", "CtxShared"], in: paths)
        defer { for f in fx { f.kill() } }
        let rules = [
            ContextRule(name: "one", path: "~/one", apps: [fx[0].id, fx[2].id]),
            ContextRule(name: "two", path: "~/two", apps: [fx[1].id, fx[2].id]),
        ]
        let (d, _) = try daemon(fx, paths, rules: rules)
        defer { d.shutdown() }
        d.contextState.current = "one"
        let r1 = d.handle(Request("context", app: "switch", value: #"{"name":"two"}"#))
        #expect(r1.ok, "\(r1.text)")
        #expect(eventually { paused(fx[0]) && running(fx[1]) && running(fx[2]) })
        #expect(d.journal.read().stashes.map(\.name) == ["context:one"])
        let r2 = d.handle(Request("context", app: "switch", value: #"{"name":"one"}"#))
        #expect(r2.ok, "\(r2.text)")
        #expect(eventually { running(fx[0]) && paused(fx[1]) && running(fx[2]) })
        #expect(d.handle(Request("context", app: "undo")).ok)
        #expect(eventually { paused(fx[0]) && running(fx[1]) && running(fx[2]) })
        #expect(d.contextState.current == "two")
        _ = d.pop("context:one")
        #expect(eventually { fx.allSatisfy(running) })
        #expect(d.journal.read().isEmpty)
    }

    /// X6: the daemon dies right after a switch stashed the leaving group; recovery (the
    /// next start or the watchdog) resumes and shows every app.
    @Test func crashAfterSwitchRecovers() throws {
        let paths = tempHome()
        let fx = try fixtures(["CtxC", "CtxD"], in: paths)
        defer { for f in fx { f.kill() } }
        let rules = [ContextRule(name: "one", path: "~/one", apps: [fx[0].id]), ContextRule(name: "two", path: "~/two", apps: [fx[1].id])]
        let (d, _) = try daemon(fx, paths, rules: rules)
        defer { d.shutdown() }
        d.contextState.current = "one"
        #expect(d.handle(Request("context", app: "switch", value: #"{"name":"two"}"#)).ok)
        #expect(eventually { paused(fx[0]) })
        let r = Signals.recover(journal: JournalStore(url: paths.journal))
        #expect(r.thawed == 1 && r.restored == 1)
        #expect(eventually { fx.allSatisfy(running) })
    }

    /// X7: Observe mode records "would switch" and stashes nothing; Active mode suggests,
    /// and accepting the suggestion switches.
    @Test func observeRecordsAndActiveSuggests() throws {
        let paths = tempHome()
        let fx = try fixtures(["CtxE", "CtxF"], in: paths)
        defer { for f in fx { f.kill() } }
        // Absolute project paths: the test's home is under /var/folders, which Auto-Context ignores as temporary.
        let rules = [
            ContextRule(name: "one", path: "/Users/iclear-ctx-test/one", apps: [fx[0].id]),
            ContextRule(name: "two", path: "/Users/iclear-ctx-test/two", apps: [fx[1].id]),
        ]
        let (d, _) = try daemon(fx, paths, mode: .observe, rules: rules)
        defer { d.shutdown() }
        d.contextState.current = "one"
        let enter = #"{"path":"/Users/iclear-ctx-test/two/src","source":"t"}"#
        #expect(d.handle(Request("context", app: "enter", value: enter)).ok)
        d.contextCheck()
        #expect(d.contextState.current == "two" && d.contextState.suggested == nil)
        #expect(d.journal.read().isEmpty && fx.allSatisfy(running))
        #expect(ActionLog.read(paths: paths).contains { $0.action.message?.contains("would switch one → two") == true })
        d.engine.config.mode = .active
        d.contextState.current = "one"
        _ = d.handle(Request("context", app: "enter", value: enter))
        d.contextCheck()
        #expect(d.contextState.suggested == "two" && fx.allSatisfy(running))
        #expect(d.events.contains { $0.title == "Switch to two?" })
        #expect(d.handle(Request("context", app: "accept")).ok)
        #expect(eventually { paused(fx[0]) && running(fx[1]) })
        _ = d.pop("context:one")
        #expect(eventually { fx.allSatisfy(running) })
    }

    @Test func hooksAndCommands() throws {
        for shell in ["zsh", "bash", "fish", "git"] {
            let r = run("iclear", ["hook", shell])
            #expect(r.status == 0 && r.out.contains("context enter") && r.out.contains("&"), "\(shell): \(r.out)")
        }
        #expect(run("iclear", ["hook", "tcsh"]).status != 0)
        // The hook's command is silent and quick when no daemon is running.
        let t0 = Date()
        let quiet = run("iclear", ["context", "enter", "/tmp"], env: ["ICLEAR_HOME": tempHome().home.path])
        #expect(quiet.status == 0 && quiet.out.isEmpty && Date().timeIntervalSince(t0) < 1)
    }
}
