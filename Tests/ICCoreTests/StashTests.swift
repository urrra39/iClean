import Foundation
import Testing

@testable import ICCore

@Suite struct StashPlannerTests {
    func cand(_ a: AppSnapshot, windows: Int = 1, unsaved: Bool? = false) -> StashCandidate {
        StashCandidate(app: a, windows: (0..<windows).map { _ in Rect(x: 0, y: 0, width: 400, height: 300) }, unsaved: unsaved)
    }

    func decisions(_ p: StashPlan) -> [String: StashPlanItem.Decision] {
        Dictionary(p.items.map { ($0.appID, $0.decision) }, uniquingKeysWith: { a, _ in a })
    }

    @Test func stashesOrdinaryAppsAndKeepsProtected() {
        let p = StashPlanner.plan(
            [cand(app("com.example.editor", mb: 900)), cand(app("com.apple.Terminal")), cand(app("com.example.menu", regular: false))],
            options: StashOptions(), session: SessionContext(), freeDiskMB: 100_000, config: Config())
        #expect(decisions(p) == ["com.example.editor": .stash, "com.apple.Terminal": .keep])
        #expect(p.footprintMB == 900 && p.refusal == nil)
        #expect(p.text.contains("reclaimed only as the system needs it"))
    }

    /// Safety invariant (1.0 #3): hard blocks have no override.
    @Test func hardBlocksCannotBeOverridden() {
        var audio = ActivitySignals(activeConnection: false, servingListener: false, recentWrite: false, lockHeld: false)
        audio.audioOutput = true
        var mic = audio
        mic.audioOutput = false
        mic.audioInput = true
        var dl = mic
        dl.audioInput = false
        dl.powerAssertion = true
        let opts = StashOptions(
            include: ["com.example.music", "com.example.call", "com.example.dl", "us.zoom.xos"], includeHeavy: true, forceUnsaved: true)
        let p = StashPlanner.plan(
            [
                cand(app("com.example.music", signals: audio)), cand(app("com.example.call", signals: mic)),
                cand(app("com.example.dl", signals: dl)), cand(app("us.zoom.xos")), cand(app("com.example.other")),
            ],
            options: opts, session: SessionContext(cameraInUse: true), freeDiskMB: 100_000, config: Config())
        #expect(
            decisions(p) == [
                "com.example.music": .blocked, "com.example.call": .blocked, "com.example.dl": .blocked,
                "us.zoom.xos": .blocked, "com.example.other": .stash,
            ])
    }

    @Test func softRisksNeedExplicitInclude() {
        let conn = ActivitySignals(activeConnection: true, servingListener: false, recentWrite: false, lockHeld: false)
        let risky = app("com.example.sync", signals: conn)
        let docker = app("com.docker.docker")
        let slack = app("com.tinyspeck.slackmacgap")
        var p = StashPlanner.plan(
            [cand(risky), cand(docker), cand(slack)], options: StashOptions(), session: SessionContext(),
            freeDiskMB: 100_000, config: Config())
        #expect(decisions(p).values.allSatisfy { $0 == .keep })
        #expect(p.refusal == "nothing to stash")
        #expect(p.items.first { $0.appID == "com.docker.docker" }!.notes.joined().contains("--include-heavy"))
        p = StashPlanner.plan(
            [cand(risky), cand(docker), cand(slack)],
            options: StashOptions(include: ["sync", "Slackmacgap"], includeHeavy: true), session: SessionContext(),
            freeDiskMB: 100_000, config: Config())
        #expect(decisions(p) == ["com.example.sync": .stash, "com.docker.docker": .stash, "com.tinyspeck.slackmacgap": .stash])
    }

    @Test func keepListUnsavedAndSharedWindows() {
        let p = StashPlanner.plan(
            [
                cand(app("com.example.browser", mb: 2000), windows: 3), cand(app("com.example.doc"), unsaved: true),
                cand(app("com.example.unknown"), unsaved: nil), cand(app("com.example.kept")),
            ],
            options: StashOptions(keep: ["KEPT"]), session: SessionContext(), freeDiskMB: 100_000, config: Config())
        #expect(
            decisions(p) == [
                "com.example.browser": .stash, "com.example.doc": .blocked, "com.example.unknown": .stash, "com.example.kept": .keep,
            ])
        #expect(p.items.first { $0.appID == "com.example.browser" }!.notes.joined().contains("all 3 windows"))
        #expect(p.items.first { $0.appID == "com.example.unknown" }!.notes.joined().contains("unsaved state unknown"))
        let forced = StashPlanner.plan(
            [cand(app("com.example.doc"), unsaved: true)], options: StashOptions(forceUnsaved: true),
            session: SessionContext(), freeDiskMB: 100_000, config: Config())
        #expect(forced.stashed.count == 1)
    }

    /// Safety invariant (1.0 #3): no stash without disk headroom for swap.
    @Test func refusesWithoutDiskHeadroom() {
        let p = StashPlanner.plan(
            [cand(app("com.example.big", mb: 3000))], options: StashOptions(), session: SessionContext(),
            freeDiskMB: 4000, config: Config())
        #expect(p.refusal?.contains("not enough free disk") == true)
        #expect(p.text.contains("REFUSED"))
        let ok = StashPlanner.plan(
            [cand(app("com.example.big", mb: 3000))], options: StashOptions(), session: SessionContext(),
            freeDiskMB: 5100, config: Config())
        #expect(ok.refusal == nil)
    }

    @Test func lifecycleRemindsThenExpires() {
        var s = StashRecord(name: "w", createdAt: 0, apps: [], previousFrontmost: nil)
        #expect(StashPlanner.lifecycle(s, now: 3600, maxAgeHours: 24) == (false, false))
        #expect(StashPlanner.lifecycle(s, now: 0.9 * 86400, maxAgeHours: 24) == (true, false))
        s.remindedAt = 0.9 * 86400
        #expect(StashPlanner.lifecycle(s, now: 0.95 * 86400, maxAgeHours: 24) == (false, false))
        #expect(StashPlanner.lifecycle(s, now: 86400, maxAgeHours: 24) == (false, true))
    }

    /// Red team: the Mac slept through the reminder and the limit. On wake the stash
    /// expires (pops) once, without a late reminder first.
    @Test func expiryAfterSleepPopsWithoutLateReminder() {
        let s = StashRecord(name: "w", createdAt: 0, apps: [], previousFrontmost: nil)
        #expect(StashPlanner.lifecycle(s, now: 3 * 86400, maxAgeHours: 24) == (false, true))
    }
}

@Suite struct JournalFormatTests {
    /// A 0.1.0 journal (no restorations, no stashes) still decodes.
    @Test func readsOldJournals() throws {
        let old = #"{"version":1,"entries":[{"pid":7,"startTime":70,"appID":"a","frozenAt":1}]}"#
        let j = try JSONDecoder().decode(Journal.self, from: Data(old.utf8))
        #expect(j.entries.count == 1 && j.restorations.isEmpty && j.stashes.isEmpty && j.entries[0].stash == nil)
    }

    @Test func restorationsKeepTheOriginalValueAndOnlyUndoChanges() {
        var j = Journal()
        j.record(Restoration(kind: .background, pid: 1, startTime: 10, appID: "a", previous: false, at: 0))
        j.record(Restoration(kind: .background, pid: 1, startTime: 10, appID: "a", previous: true, at: 5))  // ignored: first wins
        j.record(Restoration(kind: .hidden, pid: 2, startTime: 20, appID: "b", previous: true, at: 0))
        j.record(Restoration(kind: .hidden, pid: 3, startTime: 30, appID: "c", previous: false, at: 0))
        #expect(j.restorations.count == 3)
        // Restore only what iClear changed, and only for the same live process.
        let live: [Int32: UInt64] = [1: 10, 2: 20, 3: 99]
        let todo = Recovery.restorations(j, startTime: { live[$0] })
        #expect(todo.map(\.pid) == [1])
        j.removeRestorations(.background, [ProcessIdentity(pid: 1, startTime: 10)])
        #expect(j.restorations.count == 2 && !j.isEmpty)
        let round = try? JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(j))
        #expect(round == j)
    }

    /// Red team: the daemon dies part-way through a pop. Recovery resumes and unhides
    /// exactly what is still journaled.
    @Test func partlyPoppedStashRecoversTheRest() {
        var j = Journal()
        j.add([JournalEntry(pid: 2, startTime: 20, appID: "b", frozenAt: 0, stash: "w")])
        j.record(Restoration(kind: .hidden, pid: 2, startTime: 20, appID: "b", previous: false, at: 0))
        var popped = StashedApp(
            appID: "a", name: "A", processes: [ProcessIdentity(pid: 1, startTime: 10)], wasHidden: false, windows: [], order: 0,
            residentMB: 1)
        popped.popped = true
        let rest = StashedApp(
            appID: "b", name: "B", processes: [ProcessIdentity(pid: 2, startTime: 20)], wasHidden: false, windows: [], order: 1,
            residentMB: 1)
        j.stashes = [StashRecord(name: "w", createdAt: 0, apps: [popped, rest], previousFrontmost: nil)]
        let live: [Int32: UInt64] = [1: 10, 2: 20]
        #expect(Recovery.plan(j, startTime: { live[$0] }) == [.thaw(j.entries[0])])
        #expect(Recovery.restorations(j, startTime: { live[$0] }).map(\.pid) == [2])
    }

    @Test func rectDistance() {
        #expect(Rect(x: 0, y: 0, width: 10, height: 10).distance(to: Rect(x: 3, y: -1, width: 10, height: 12)) == 3)
    }
}
