import Foundation
import Testing

@testable import ICCore
@testable import ICSystem

/// The Panic Brake on spawned ic-hog processes, with injected stall signals.
@Suite(.serialized) struct BrakeIntegrationTests {
    final class Feed {
        var t = 0.0
        var swap: UInt64 = 0
        var dec: UInt64 = 0
        /// One reading a second: a storm (critical pressure, swap-ins, late timers) or calm.
        func next(_ a: BrakeAgent, storm: Bool) {
            t += 1
            if storm {
                swap += 20_000
                dec += 80_000
            }
            a.ingest(StallSignals(t: t, pressure: storm ? 4 : 1, swapIns: swap, decompressions: dec, jitterMs: storm ? 400 : 1))
            a.work(now: t)
        }
    }

    func agent(_ probe: FakeProbe, mode: BrakeMode) -> BrakeAgent {
        let a = BrakeAgent(paths: tempHome(), probe: probe)
        a.settings.mode = mode
        a.ladder.settings = a.settings
        return a
    }

    func app(_ h: SpawnedHog, _ id: String, _ mb: Double) -> AppSnapshot {
        AppSnapshot(id: id, name: id, processes: [h.identity!], footprintMB: mb)
    }

    @Test func pausesTheCulpritAndKeepsItWhenTheStallClears() throws {
        let a1 = try hog()
        let b1 = try hog()
        defer {
            a1.kill()
            b1.kill()
        }
        let probe = FakeProbe()
        probe.apps = [app(a1, "Grower", 500), app(b1, "Calm", 300)]
        let a = agent(probe, mode: .on)
        let f = Feed()
        a.clock = { f.t }
        f.next(a, storm: false)
        f.next(a, storm: true)
        f.next(a, storm: true)  // stalled; the first tree sample has no growth yet
        #expect(!isStopped(a1.pid))
        probe.apps = [app(a1, "Grower", 900), app(b1, "Calm", 300)]
        f.next(a, storm: true)
        #expect(isStopped(a1.pid) && !isStopped(b1.pid))
        #expect(a.journal.read().entries.map(\.pid) == [a1.pid])
        for _ in 0..<4 { f.next(a, storm: false) }
        #expect(a.pauses["Grower"] != nil && isStopped(a1.pid))
        #expect(a.events.contains { $0.title == "Panic Brake paused Grower" })
        let codes = ActionLog.read(paths: a.paths).flatMap { $0.action.reasons.map(\.code) }
        #expect(codes.contains(Code.panicPause) && codes.contains(Code.panicConfirmed))
        #expect(a.handle(Request("resume", app: "Grower")).ok)
        #expect(!isStopped(a1.pid) && a.journal.read().isEmpty && a.pauses.isEmpty)
    }

    @Test func wrongGuessIsResumedThenTheNextIsTriedThenItGivesUp() throws {
        let a1 = try hog()
        let b1 = try hog()
        defer {
            a1.kill()
            b1.kill()
        }
        let probe = FakeProbe()
        probe.apps = [app(a1, "Big", 500), app(b1, "Small", 300)]
        let a = agent(probe, mode: .on)
        let f = Feed()
        a.clock = { f.t }
        f.next(a, storm: false)
        f.next(a, storm: true)
        f.next(a, storm: true)
        probe.apps = [app(a1, "Big", 900), app(b1, "Small", 350)]
        f.next(a, storm: true)
        #expect(isStopped(a1.pid))
        for _ in 0..<4 { f.next(a, storm: true) }
        #expect(!isStopped(a1.pid) && isStopped(b1.pid))
        for _ in 0..<5 { f.next(a, storm: true) }
        #expect(!isStopped(a1.pid) && !isStopped(b1.pid))
        #expect(a.events.contains { $0.title == "Mac still stalled" })
        #expect(a.journal.read().isEmpty && a.pauses.isEmpty)
    }

    @Test func observeModeTouchesNothing() throws {
        let a1 = try hog()
        defer { a1.kill() }
        let probe = FakeProbe()
        probe.apps = [app(a1, "Grower", 500)]
        let a = agent(probe, mode: .observe)
        let f = Feed()
        a.clock = { f.t }
        f.next(a, storm: false)
        f.next(a, storm: true)
        f.next(a, storm: true)
        probe.apps = [app(a1, "Grower", 900)]
        for _ in 0..<8 { f.next(a, storm: true) }
        #expect(!isStopped(a1.pid) && a.journal.read().isEmpty)
        let would = ActionLog.read(paths: a.paths).filter { $0.action.reasons.contains { $0.code == Code.panicWould } }
        #expect(would.count == 1 && would.first?.action.dryRun == true)
    }

    /// The real watchdog process in lab mode: a simulated stall pauses the registered
    /// runaway (and nothing else); after `kill -9` its watchdog child resumes it.
    @Test func icbrakePausesTheRunawayAndItsWatchdogRecovers() throws {
        let paths = tempHome()
        let runaway = try hog(["--mb", "150", "--grow-mbps", "20"])
        let calm = try hog(["--mb", "150"])
        defer {
            runaway.kill()
            calm.kill()
        }
        try JSONEncoder().encode([runaway.identity!, calm.identity!]).write(to: paths.labRegistry)
        var c = Config()
        c.brake.mode = .on
        try c.encoded().write(to: paths.config)
        let p = Process()
        p.executableURL = products.appendingPathComponent("icbrake")
        p.environment = ProcessInfo.processInfo.environment.merging(["ICLEAR_HOME": paths.home.path, "ICLEAR_LAB": "1"]) { _, n in n }
        try p.run()
        defer { if p.isRunning { p.terminate() } }
        #expect(eventually(10) { IPC.send(Request("ping"), path: paths.brakeSocket.path, timeout: 1)?.ok == true })
        #expect(IPC.send(Request("simulate", value: "on"), path: paths.brakeSocket.path)?.ok == true)
        let t0 = Date()
        let paused = eventually(8) { isStopped(runaway.pid) }
        #expect(paused)
        if !paused {
            print("DEBUG status", IPC.send(Request("status"), path: paths.brakeSocket.path)?.data ?? "-")
            print("DEBUG trees", IPC.send(Request("trees"), path: paths.brakeSocket.path)?.data ?? "-")
            print("DEBUG log", ActionLog.read(paths: paths).map { $0.action.message ?? "" })
        }
        let pausedAfter = Date().timeIntervalSince(t0)
        #expect(pausedAfter < 8 && !isStopped(calm.pid))
        #expect(eventually(8) { FileManager.default.fileExists(atPath: paths.blackBox.path) })
        kill(p.processIdentifier, SIGKILL)
        p.waitUntilExit()
        #expect(eventually(2) { !isStopped(runaway.pid) })
        #expect(!isStopped(calm.pid))
        let box = try Files.readJSON([BlackBoxSample].self, from: paths.blackBox) ?? []
        #expect(box.contains { $0.state == .stalled })
    }
}
