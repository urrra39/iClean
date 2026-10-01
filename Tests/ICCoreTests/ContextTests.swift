import Foundation
import Testing

@testable import ICCore

@Suite struct ContextTests {
    let home = "/Users/dev"
    var rules: [ContextRule] {
        [
            ContextRule(name: "web", path: "~/code/web", apps: ["com.google.Chrome", "Figma"]),
            ContextRule(name: "api", path: "~/code/api", apps: ["com.microsoft.VSCode", "Postman", "com.google.Chrome"], keep: ["Slack"]),
            ContextRule(name: "any", path: "~/code/*", apps: ["com.apple.TextEdit"]),
            ContextRule(name: "release", path: "~/code/web", apps: ["Xcode"], branch: "release/*"),
        ]
    }
    var settings: ContextSettings { ContextSettings() }

    @Test func resolveMostSpecificGlobAndBranch() {
        #expect(ContextTracker.resolve(path: "/Users/dev/code/web/src/ui", branch: "main", rules: rules, home: home)?.name == "web")
        #expect(ContextTracker.resolve(path: "/Users/dev/code/other", branch: nil, rules: rules, home: home)?.name == "any")
        #expect(ContextTracker.resolve(path: "/Users/dev/code/web", branch: "release/1.0", rules: rules, home: home)?.name == "release")
        #expect(ContextTracker.resolve(path: "/Users/dev/docs", branch: nil, rules: rules, home: home) == nil)
        #expect(ContextTracker.ignored("/Users/dev", home: home) && ContextTracker.ignored("/tmp/x", home: home))
        #expect(ContextTracker.ignored("/private/var/folders/ab/T", home: home) && !ContextTracker.ignored("/Users/dev/code", home: home))
    }

    func enter(_ s: inout ContextState, _ path: String, at t: Double, source: String = "tty1") {
        ContextTracker.enter(&s, path: path, branch: nil, source: source, now: t, rules: rules, settings: settings, home: home)
    }

    /// The dwell time starts when a context is entered; moves inside it do not restart it.
    @Test func dwellAndSubdirectories() {
        var s = ContextState()
        s.current = "web"
        enter(&s, "/Users/dev/code/api", at: 0)
        #expect(ContextTracker.decide(&s, now: 10, rules: rules, settings: settings, mode: .active) == .none)
        enter(&s, "/Users/dev/code/api/Sources", at: 12)
        #expect(ContextTracker.dueAt(s, settings: settings) == 20)
        #expect(ContextTracker.decide(&s, now: 20, rules: rules, settings: settings, mode: .active) == .suggest(from: "web", to: "api"))
        // The same suggestion is not repeated.
        enter(&s, "/Users/dev/code/api", at: 30)
        #expect(ContextTracker.decide(&s, now: 60, rules: rules, settings: settings, mode: .active) == .none)
    }

    /// X4: things that must not switch.
    @Test func falseTriggersAreIgnored() {
        var s = ContextState()
        s.current = "web"
        // Back to the current context within the dwell time cancels.
        enter(&s, "/Users/dev/code/api", at: 0)
        enter(&s, "/Users/dev/code/web", at: 5)
        #expect(s.pending == nil)
        // Home and temporary folders do nothing, and do not cancel or start anything.
        enter(&s, "/tmp/build", at: 6)
        enter(&s, "/Users/dev", at: 7)
        #expect(s.pending == nil)
        // A different shell asking for a different context during the dwell time is a tie: keep the current one.
        enter(&s, "/Users/dev/code/api", at: 10, source: "tty1")
        enter(&s, "/Users/dev/code/other", at: 12, source: "tty2")
        #expect(s.pending == nil && s.current == "web")
        // Directories outside every context do nothing.
        enter(&s, "/Users/dev/docs", at: 20)
        #expect(s.pending == nil)
    }

    /// No second switch inside the cooldown; it happens once the cooldown is over.
    @Test func cooldown() {
        var s = ContextState()
        s.current = "web"
        s.lastSwitch = ContextSwitchRecord(from: nil, to: "web", at: 0, stashed: [], popped: [])
        enter(&s, "/Users/dev/code/api", at: 30)
        #expect(ContextTracker.decide(&s, now: 100, rules: rules, settings: settings, mode: .active) == .none)
        #expect(ContextTracker.dueAt(s, settings: settings) == 300)
        #expect(ContextTracker.decide(&s, now: 300, rules: rules, settings: settings, mode: .active) == .suggest(from: "web", to: "api"))
    }

    /// X7: suggest by default; automatic only when the context opts in and in Active
    /// mode; Observe mode records "would switch" and nothing else.
    @Test func modes() {
        var auto = rules
        auto[1].auto = true
        var s = ContextState()
        s.current = "web"
        ContextTracker.enter(&s, path: "/Users/dev/code/api", branch: nil, source: "t", now: 0, rules: auto, settings: settings, home: home)
        var o = s
        #expect(ContextTracker.decide(&s, now: 20, rules: auto, settings: settings, mode: .active) == .switchNow(from: "web", to: "api"))
        #expect(ContextTracker.decide(&o, now: 20, rules: auto, settings: settings, mode: .observe) == .wouldSwitch(from: "web", to: "api"))
        #expect(o.current == "api" && o.suggested == nil && o.lastSwitch?.stashed == [] && o.lastSwitch?.popped == [])
        var paused = ContextState()
        paused.paused = true
        enter(&paused, "/Users/dev/code/api", at: 0)
        #expect(ContextTracker.decide(&paused, now: 100, rules: rules, settings: settings, mode: .active) == .none)
    }

    /// An app both contexts use, or one either context keeps, stays running.
    @Test func planKeepsSharedApps() {
        let running = [
            app("com.google.Chrome"), app("com.microsoft.VSCode"), app("com.getpostman.postman"), app("com.tinyspeck.slackmacgap"),
            app("com.figma.Desktop"),
        ]
        var named = running
        named[2].name = "Postman"
        named[3].name = "Slack"
        named[4].name = "Figma"
        let r = rules
        let p = ContextPlanner.plan(from: r[1], to: r[0], running: named)
        #expect(p.stash.sorted() == ["com.getpostman.postman", "com.microsoft.VSCode"])
        #expect(p.keepRunning == ["com.google.Chrome"])
        #expect(ContextPlanner.plan(from: nil, to: r[0], running: named).stash.isEmpty)
    }

    @Test func suggestionsFromActivity() {
        var s = ContextState()
        s.lastRoot = "/Users/dev/code/web"
        for _ in 0..<5 { ContextTracker.noteActivation(&s, appID: "com.figma.Desktop") }
        for _ in 0..<3 { ContextTracker.noteActivation(&s, appID: "com.google.Chrome") }
        ContextTracker.noteActivation(&s, appID: "com.apple.Notes")
        #expect(ContextTracker.suggestApps(s, root: "/Users/dev/code/web") == ["com.figma.Desktop", "com.google.Chrome"])
        #expect(ContextTracker.suggestApps(s, root: "/Users/dev/elsewhere").isEmpty)
    }

    @Test func configAndDecoding() throws {
        let r = try JSONDecoder().decode(ContextRule.self, from: Data(#"{"name":"w","path":"~/w","apps":["A"]}"#.utf8))
        #expect(r.keep.isEmpty && r.branch == nil && !r.auto)
        var c = Config()
        c.contexts = [ContextRule(name: "a b", path: "~/x", apps: ["A"]), ContextRule(name: "z", path: "", apps: [])]
        #expect(c.validate().filter { $0.path.hasPrefix("contexts[") }.count == 2)
        c.contexts = [ContextRule(name: "w", path: "~/w", apps: ["A"]), ContextRule(name: "w", path: "~/v", apps: ["B"])]
        #expect(c.validate().contains { $0.path == "contexts" })
        let s = try JSONDecoder().decode(ContextState.self, from: Data("{}".utf8))
        #expect(s.current == nil && !s.paused)
        let o = try JSONDecoder().decode(StashOptions.self, from: Data(#"{"keep":["A"]}"#.utf8))
        #expect(o.keep == ["A"] && o.only.isEmpty && !o.dryRun)
    }

    /// A stash with `only` stashes exactly that group.
    @Test func stashOnlyTheGroup() {
        let p = StashPlanner.plan(
            [
                StashCandidate(app: app("com.a"), windows: [], unsaved: false),
                StashCandidate(app: app("com.b"), windows: [], unsaved: false),
            ],
            options: StashOptions(only: ["com.a"]), session: SessionContext(), freeDiskMB: 100_000, config: Config())
        #expect(p.stashed.map(\.appID) == ["com.a"])
        #expect(p.items.first { $0.appID == "com.b" }?.notes == ["not in this group"])
    }
}
