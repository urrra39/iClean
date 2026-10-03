import Foundation
import Testing

@testable import ICCore

@Suite struct ThrashTests {
    /// Three ticks 30 s apart; system page-ins and each app's page-ins grow by the given rates.
    func run(
        _ config: Config, pressure: PressureLevel = .warning, systemRate: UInt64 = 4000, rates: [String: UInt64],
        front: String? = nil, cpu: Double = 20
    ) -> [Action] {
        let e = Engine(config: config, hardware: hw16, state: EngineState(startedAt: 0))
        var all: [Action] = []
        for i in 0..<3 {
            let t = Double(i) * 30
            var s = sample(t, pressure)
            s.pageIns = UInt64(i) * systemRate * 30
            let apps = rates.keys.sorted().map { id -> AppSnapshot in
                var a = app(id, mb: 800, cpu: cpu, front: id == front)
                a.pageIns = UInt64(i) * rates[id]! * 30
                a.wakeups = UInt64(i) * 50 * 30
                return a
            }
            all += e.tick(TickInput(sample: s, apps: apps, weekday: 3, hour: 10)).actions
        }
        return all
    }

    func thrashFreezes(_ a: [Action]) -> [String] {
        a.filter { $0.kind == .freeze && $0.reasons.contains { $0.code == Code.thrashPageIn } }.map(\.appID)
    }

    @Test func pausesTheTopBackgroundOffendersOnly() {
        let c = activeConfig { $0.thrash.enabled = true }
        let rates: [String: UInt64] = [
            "com.example.waker": 400, "com.example.small": 150, "com.example.quiet": 5, "com.tinyspeck.slackmacgap": 900,
            "com.example.front": 1000, "com.example.third": 120,
        ]
        let a = run(c, rates: rates, front: "com.example.front")
        // Two at most per episode, highest rate first; COMM, frontmost and quiet apps are not paused.
        #expect(thrashFreezes(a) == ["com.example.waker", "com.example.small"])
        #expect(a.first { $0.appID == "com.example.waker" }?.dryRun == false)
    }

    @Test func needsTheEpisodeTheSettingAndActiveMode() {
        let rates: [String: UInt64] = ["com.example.waker": 400]
        #expect(thrashFreezes(run(activeConfig(), rates: rates)).isEmpty)  // off by default
        let on = activeConfig { $0.thrash.enabled = true }
        #expect(thrashFreezes(run(on, pressure: .normal, rates: rates)).isEmpty)  // no warning pressure, no stall
        #expect(thrashFreezes(run(on, systemRate: 500, rates: rates)).isEmpty)  // no page-in storm
        var observe = on
        observe.mode = .observe
        let o = run(observe, rates: rates).filter { $0.reasons.contains { $0.code == Code.thrashPageIn } }
        #expect(o.count == 1 && o.allSatisfy(\.dryRun))  // Observe records only
        #expect(!Config().thrash.enabled)
        var bad = Config()
        bad.thrash.maxAppsPerEpisode = 0
        #expect(bad.validate().contains { $0.path == "thrash" })
    }

    @Test func calibrationFilesWithoutNewerFieldsStillLoad() throws {
        let old = #"{"swapInsPerSecond":300,"decompressionsPerSecond":9000,"jitterMs":100,"probeMs":2000,"loadPerCore":1.5}"#
        let c = try JSONDecoder().decode(StallCalibration.self, from: Data(old.utf8))
        #expect(c.swapInsPerSecond == 300 && c.pageInsPerSecond == 2000)
    }
}
