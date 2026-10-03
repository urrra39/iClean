import Foundation
import Testing

@testable import ICCore
@testable import ICSystem

/// A freeze journal that cannot be decoded: never replaced by a new write, never moved
/// aside by a read, and handled by recovery when the daemon meets it.
@Suite(.serialized) struct JournalFaultTests {
    @Test func corruptJournalIsNeverReplacedByANewWrite() throws {
        let paths = tempHome()
        let j = JournalStore(url: paths.journal)
        try Data("{\"entries\": [ {\"pid\": 12".utf8).write(to: paths.journal)  // torn
        #expect(throws: JournalStore.CorruptJournal.self) {
            try j.update { $0.add([JournalEntry(pid: 1, startTime: 1, appID: "new", frozenAt: 0)]) }
        }
        _ = j.read()
        #expect(try Data(contentsOf: paths.journal) == Data("{\"entries\": [ {\"pid\": 12".utf8))  // untouched
        let h = try hog()
        defer { h.kill() }
        let r = Signals.freezeTree([h.identity!], appID: "x", at: 0, journal: j)
        #expect(!r.ok && r.error?.contains("corrupt") == true && !isStopped(h.pid))
    }

    @Test func daemonRecoversWhenItMeetsACorruptJournal() throws {
        let h = try hog()
        defer { h.kill() }
        let probe = FakeProbe()
        probe.apps = [AppSnapshot(id: "com.example.j", name: "J", processes: [h.identity!], residentMB: 20, footprintMB: 20)]
        let paths = tempHome()
        let d = try testDaemon(probe, paths: paths)
        defer { d.shutdown() }
        d.tick()
        try Data("not json".utf8).write(to: paths.journal)
        _ = d.journal.read()
        #expect(FileManager.default.fileExists(atPath: paths.journal.path))
        _ = d.handle(Request("freeze", app: "com.example.j"))
        #expect(!isStopped(h.pid))
        let aside = try FileManager.default.contentsOfDirectory(atPath: paths.base.path).filter { $0.hasPrefix("journal.json.corrupt-") }
        #expect(aside.count == 1 && !FileManager.default.fileExists(atPath: paths.journal.path))
        #expect(d.handle(Request("freeze", app: "com.example.j")).ok && isStopped(h.pid))
        _ = d.handle(Request("thaw", app: "all"))
    }
}
