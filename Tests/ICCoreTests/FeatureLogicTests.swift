import Foundation
import Testing

@testable import ICCore

@Suite struct BatteryPlannerTests {
    func calibrated(scale: Double = 1, base: Double = 3, noise: Double = 0) -> PowerCalibration {
        var c = PowerCalibration()
        for i in 0..<30 {
            let p = Double(i % 10) + 1
            c.add(processWatts: p, batteryWatts: base + scale * p + (i % 2 == 0 ? noise : -noise))
        }
        return c
    }

    @Test func calibrationFit() {
        let f = calibrated(scale: 1.2, base: 4).fit
        #expect(abs(f.scale - 1.2) < 1e-6 && abs(f.base - 4) < 1e-6 && f.residualSD < 1e-6 && f.n == 30)
        #expect(PowerCalibration().fit.n == 0 && PowerCalibration().confidence.hasPrefix("low"))
        #expect(calibrated().confidence.hasPrefix("high"))
        // Physically impossible slopes fall back to 1.
        var weird = PowerCalibration()
        for i in 0..<10 { weird.add(processWatts: Double(i), batteryWatts: 100 - 20 * Double(i)) }
        #expect(weird.fit.scale == 1)
        var many = PowerCalibration()
        for i in 0..<(PowerCalibration.maxPoints + 10) { many.add(processWatts: Double(i), batteryWatts: Double(i)) }
        #expect(many.points.count == PowerCalibration.maxPoints)
    }

    @Test func minutesAndGainAreRangesInMinutes() {
        #expect(BatteryPlanner.minutes(remainingWh: 50, watts: 10) == 300)
        #expect(BatteryPlanner.minutes(remainingWh: 50, watts: 0.1) == nil)
        let g = BatteryPlanner.gain(remainingWh: 50, systemW: 10, appW: 2, calibration: calibrated(noise: 0.5))!
        // 50 Wh at 8 W = 375 min vs 300 min now: about 75 min, widened by the residual.
        #expect(g.low < 75 && g.high > 75 && g.low >= 0)
        #expect(BatteryPlanner.gain(remainingWh: 50, systemW: 10, appW: 0, calibration: calibrated()) == nil)
    }

    @Test func targetPlanPicksCheapestWattsFirstAndReportsUnreachable() {
        let c = calibrated()
        let cands: [(app: AppPower, cost: Double)] = [
            (AppPower(appID: "a", name: "A", watts: 4), 2),
            (AppPower(appID: "b", name: "B", watts: 3), 0.1),
            (AppPower(appID: "c", name: "C", watts: 0.01), 0),
        ]
        // 30 Wh for 3 h needs 10 W; drawing 14 W: pausing B (cheap) is not enough, then A.
        let p = BatteryPlanner.plan(remainingWh: 30, hours: 3, systemW: 14, candidates: cands, calibration: c)
        #expect(p.pause == ["b", "a"] && p.reachable)
        let far = BatteryPlanner.plan(remainingWh: 30, hours: 10, systemW: 14, candidates: cands, calibration: c)
        #expect(!far.reachable && far.bestCaseHours < 10 && far.bestCaseHours > 2)
    }

    /// Safety invariant (1.0 #5): estimates self-disarm on poor measured accuracy.
    @Test func receiptsDisarmUnreliableEstimates() {
        var s = BatteryState()
        #expect(s.reliable && s.medianError == nil)
        s.receipts = [10, 10.5, 11].map { BatteryReceipt(at: 0, action: "x", predictedW: 10, measuredW: $0) }
        #expect(s.reliable && abs(s.medianError! - 0.05) < 1e-9)
        s.receipts = [14, 15, 16].map { BatteryReceipt(at: 0, action: "x", predictedW: 10, measuredW: $0) }
        #expect(!s.reliable)
    }
}

@Suite struct ShieldTests {
    var on: ShieldSettings {
        var s = ShieldSettings()
        s.enabled = true
        s.interferenceMs = 2
        s.judgeAfter = 3
        return s
    }

    @Test func offByDefaultAndWithoutTrigger() {
        var st = ShieldState()
        #expect(Shield.step(&st, triggerActive: true, interference: 50, settings: ShieldSettings()) == .off)
        #expect(Shield.step(&st, triggerActive: false, interference: 50, settings: on) == .off)
    }

    /// Escalates only while interference is measured; steps down at once when it clears.
    @Test func ladderClimbsOnlyOnMeasuredInterference() {
        var st = ShieldState()
        #expect(Shield.step(&st, triggerActive: true, interference: 1, settings: on) == .off)  // idle Mac: nothing
        #expect(Shield.step(&st, triggerActive: true, interference: nil, settings: on) == .off)
        #expect(Shield.step(&st, triggerActive: true, interference: 5, settings: on) == .off)  // one strike
        #expect(Shield.step(&st, triggerActive: true, interference: 5, settings: on) == .background)
        #expect(Shield.step(&st, triggerActive: true, interference: 1, settings: on) == .off)  // cleared
        #expect(Shield.step(&st, triggerActive: false, interference: nil, settings: on) == .off)
    }

    /// Safety invariant (1.0 #4): the shield switches itself off when escalating does not help.
    @Test func disarmsWhenItDoesNotHelp() {
        var st = ShieldState()
        // Escalating never lowers interference: each episode climbs, sees no change, clears.
        for _ in 0..<4 {
            _ = Shield.step(&st, triggerActive: true, interference: 5, settings: on)
            _ = Shield.step(&st, triggerActive: true, interference: 5, settings: on)  // escalates
            _ = Shield.step(&st, triggerActive: true, interference: 5, settings: on)  // scored: 0% better
            _ = Shield.step(&st, triggerActive: true, interference: 1, settings: on)
        }
        #expect(st.disarmed && st.message?.contains("switched itself off") == true)
        #expect(Shield.step(&st, triggerActive: true, interference: 50, settings: on) == .off)
    }

    @Test func keepsWorkingWhenItHelps() {
        var st = ShieldState()
        for _ in 0..<10 {
            _ = Shield.step(&st, triggerActive: true, interference: 6, settings: on)
            _ = Shield.step(&st, triggerActive: true, interference: 6, settings: on)  // escalates
            _ = Shield.step(&st, triggerActive: true, interference: 1, settings: on)  // big improvement, steps down
        }
        #expect(!st.disarmed && st.improvements.count >= 3)
    }

    /// Red team: microphone released and taken again within seconds does not flap.
    @Test func callEndIsDebounced() {
        var d = CallDetector()
        #expect(d.update(signal: true, now: 0) == (true, true))
        #expect(d.update(signal: false, now: 1) == (true, false))  // mute or a gap
        #expect(d.update(signal: true, now: 1.2) == (true, false))
        #expect(d.update(signal: false, now: 2.0) == (true, false))
        #expect(d.update(signal: false, now: 2.8) == (false, true))  // 1.6 s without a signal: ended
        #expect(d.startedAt == nil)
    }
}

@Suite struct ForensicsAndAdvisorTests {
    func event(_ edit: (inout StallEvent) -> Void = { _ in }) -> StallEvent {
        var e = StallEvent(
            at: 0, appID: "a", name: "App", durationMs: 900, pageinsPerSec: 0, swapinsPerSec: 0, busyCores: 1, cores: 8,
            pressure: .normal, thermal: .nominal, offenders: [Offender(name: "Big", cpuPercent: 700, diskMBps: 120)])
        edit(&e)
        return e
    }

    @Test func explanations() {
        #expect(Forensics.explain(event()).first?.hasPrefix("disk: Big") == true)
        #expect(Forensics.explain(event { $0.swapinsPerSec = 500 }).first?.hasPrefix("memory") == true)
        #expect(Forensics.explain(event { $0.busyCores = 8 }).contains { $0.hasPrefix("CPU: all 8 cores") })
        #expect(Forensics.explain(event { $0.thermal = .critical }).contains { $0.hasPrefix("heat") })
        let none = Forensics.explain(event { $0.offenders = [] })
        #expect(none.count == 1 && none[0].contains("the app itself"))
        #expect(
            Forensics.explain(
                event {
                    $0.offenders = []
                    $0.pageinsPerSec = 5000
                }
            ).first?.hasPrefix("disk reads") == true)
    }

    @Test func stats() {
        #expect(Forensics.stats([]) == "No stalls recorded.")
        var e = event()
        e.causes = Forensics.explain(e)
        let s = Forensics.stats([e, e])
        #expect(s.hasPrefix("2 stalls") && s.contains("App 2"))
    }

    @Test func launchAdvisor() {
        let s = SystemSample(time: 0, availablePercent: 40, physicalMB: 16000)  // 6400 MB available
        let thin = AppUsage(name: "Big", samples: 5, idleSamples: 0, residentSumMB: 5000, since: 0)
        #expect(!LaunchAdvisor.advise(name: "Big", usage: thin, sample: s, warningLevel: 25, pausable: []).enoughData)
        #expect(!LaunchAdvisor.advise(name: "Big", usage: nil, sample: s, warningLevel: 25, pausable: []).enoughData)
        let small = AppUsage(name: "Small", samples: 100, idleSamples: 0, residentSumMB: 100 * 500, since: 0, maxMB: 800)
        #expect(LaunchAdvisor.advise(name: "Small", usage: small, sample: s, warningLevel: 25, pausable: []).verdict == "fits")
        let big = AppUsage(name: "Big", samples: 100, idleSamples: 0, residentSumMB: 100 * 3500, since: 0, maxMB: 5000)
        let a = LaunchAdvisor.advise(name: "Big", usage: big, sample: s, warningLevel: 25, pausable: [("Editor", 2000), ("Chat", 300)])
        #expect(a.verdict.hasPrefix("likely pushes") && a.suggestions == ["Editor", "Chat"] && a.text.hasPrefix("ESTIMATE"))
        let tight = AppUsage(name: "Mid", samples: 100, idleSamples: 0, residentSumMB: 100 * 2000, since: 0, maxMB: 3000)
        #expect(LaunchAdvisor.advise(name: "Mid", usage: tight, sample: s, warningLevel: 25, pausable: []).verdict.hasPrefix("tight"))
    }
}
