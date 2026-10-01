import Foundation
import Testing

@testable import ICCore
@testable import ICSystem

/// Call Mode against a simulated call (ic-call-sim opens the microphone). Skipped where
/// no microphone can be opened (for example CI runners).
@Suite(.serialized) struct CallModeTests {
    func daemonWithShield(_ probe: FakeProbe, mode: Mode) throws -> Daemon {
        try testDaemon(probe, mode: mode) { c in
            c.callMode.enabled = true
            c.callMode.interferenceMs = 0.000_001  // any measured lateness counts: forces the ladder to climb
            c.callMode.maxLevel = .background
        }
    }

    func waitFor(_ d: Daemon, _ seconds: Double, _ cond: () -> Bool) -> Double? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < seconds {
            d.shieldPoll()
            if cond() { return Date().timeIntervalSince(t0) }
            usleep(250_000)
        }
        return nil
    }

    @Test func callModeLowersOthersAndRestoresWithinTwoSeconds() throws {
        let other = try hog(["--cpu"])
        let call = try SpawnedHog(path: products.appendingPathComponent("ic-call-sim").path, args: ["--audio"])
        defer {
            other.kill()
            call.kill()
        }
        _ = call.waitReady()
        guard eventually(5, { AudioActivity.pids().input.contains(call.pid) }) else {
            print("SKIP: no microphone input available")
            return
        }
        let probe = FakeProbe()
        var busy = hogApp("test.busy", [other])
        busy.cpuPercent = 90
        var callApp = hogApp("test.call", [call])
        callApp.cpuPercent = 50
        probe.apps = [busy, callApp]
        let d = try daemonWithShield(probe, mode: .active)
        defer { d.shutdown() }
        #expect(waitFor(d, 10) { Proc.isBackground(other.pid) } != nil)
        // Safety invariant (1.0 #4): the call's own process is never touched.
        #expect(!Proc.isBackground(call.pid))
        #expect(d.journal.read().restorations.contains { $0.identity == other.identity! && !$0.previous })
        call.kill()
        let restored = waitFor(d, 5) { !Proc.isBackground(other.pid) }
        #expect(restored != nil && restored! <= 2.5, "restored after \(String(describing: restored)) s")
        #expect(d.callDetections == 1)
    }

    @Test func observeModeOnlyRecords() throws {
        let other = try hog(["--cpu"])
        let call = try SpawnedHog(path: products.appendingPathComponent("ic-call-sim").path, args: ["--audio"])
        defer {
            other.kill()
            call.kill()
        }
        _ = call.waitReady()
        guard eventually(5, { AudioActivity.pids().input.contains(call.pid) }) else { return }
        let probe = FakeProbe()
        var busy = hogApp("test.busy", [other])
        busy.cpuPercent = 90
        probe.apps = [busy]
        let d = try daemonWithShield(probe, mode: .observe)
        defer { d.shutdown() }
        _ = waitFor(d, 4) { ActionLog.read(paths: d.paths).contains { $0.outcome == "observe" && $0.action.kind == .deprioritize } }
        #expect(ActionLog.read(paths: d.paths).contains { $0.outcome == "observe" && $0.action.kind == .deprioritize })
        #expect(!Proc.isBackground(other.pid))
    }

    @Test func featureCommandsAnswer() throws {
        let d = try testDaemon(FakeProbe())
        defer { d.shutdown() }
        #expect(d.handle(Request("battery")).ok)
        let t = d.handle(Request("battery", value: "2h"))
        #expect(!t.ok && t.text.contains("experimental"))
        #expect(d.handle(Request("battery", value: "off")).ok)
        #expect(d.handle(Request("beachball")).ok && d.handle(Request("beachball", value: "log")).ok)
        #expect(!d.handle(Request("before", app: "nothing-like-this")).ok)
        #expect(d.handle(Request("shield")).text.contains("call: level 0"))
        #expect(Daemon.parseDuration("2h30m") == 9000 && Daemon.parseDuration("45") == 2700 && Daemon.parseDuration("x") == nil)
    }
}
