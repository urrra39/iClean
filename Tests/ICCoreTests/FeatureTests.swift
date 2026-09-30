import Foundation
import Testing
@testable import ICCore

@Suite struct JournalTests {
    let e1 = JournalEntry(pid: 10, startTime: 111, appID: "com.a", frozenAt: 1)
    let e2 = JournalEntry(pid: 11, startTime: 222, appID: "com.a", frozenAt: 1)
    let e3 = JournalEntry(pid: 20, startTime: 333, appID: "com.b", frozenAt: 2)

    @Test func addRemoveDedupe() {
        var j = Journal()
        j.add([e1, e2])
        j.add([e1, e3])
        #expect(j.entries == [e1, e2, e3])
        #expect(j.appIDs == ["com.a", "com.b"])
        j.remove(appID: "com.a")
        #expect(j.entries == [e3])
        j.remove([e3.identity])
        #expect(j.entries.isEmpty)
    }

    /// Safety invariant 2 (logic): only exact PID + start-time matches are thawed.
    @Test func recoveryNeverSignalsReusedPIDs() {
        let j = Journal(entries: [e1, e2, e3])
        let now: [Int32: UInt64] = [10: 111, 11: 999]  // 11 was reused, 20 is gone
        let plan = Recovery.plan(j) { now[$0] }
        #expect(plan == [.thaw(e1), .stale(e2), .stale(e3)])
    }

    @Test func codableRoundTrip() throws {
        let j = Journal(entries: [e1, e3])
        let back = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(j))
        #expect(back == j)
    }
}

@Suite struct HealthTests {
    @Test func healthyMachineScores100() {
        let h = Health.score(sample(0), swapOutMBPerMinute: 0, runawayApps: 0)
        #expect(h.score == 100 && h.band == .good && h.penalties.isEmpty)
    }

    @Test func penaltiesAddUpAndClamp() {
        var s = sample(0, .critical, thermal: .critical, disk: 3)
        s.compressedMB = 8000
        let h = Health.score(s, swapOutMBPerMinute: 500, runawayApps: 5)
        #expect(h.score == 0 && h.band == .poor)
        #expect(Health.score(sample(0, .warning), swapOutMBPerMinute: 0, runawayApps: 0).score == 75)
        #expect(Health.score(sample(0, .warning), swapOutMBPerMinute: 0, runawayApps: 0).band == .fair)
        #expect(Health.score(sample(0, thermal: .fair), swapOutMBPerMinute: 0, runawayApps: 0).score == 95)
        #expect(Health.score(sample(0, thermal: .serious), swapOutMBPerMinute: 0, runawayApps: 0).score == 85)
        #expect(Health.score(sample(0, disk: 8), swapOutMBPerMinute: 0, runawayApps: 0).score == 90)
        #expect(Health.score(sample(0), swapOutMBPerMinute: 50, runawayApps: 1).score == 85)
    }

    @Test func swapRate() {
        let a = sample(0, swapOuts: 0), b = sample(60, swapOuts: 6400)  // 6400 x 16 KB = 100 MB
        #expect(Health.swapOutRate(a, b) == 100)
        #expect(Health.swapOutRate(b, a) == 0)
    }

    @Test func thawOutcome() {
        #expect(ThawOutcome(alive: true, responsive: nil).healthy)
        #expect(!ThawOutcome(alive: true, responsive: false).healthy)
        #expect(!ThawOutcome(alive: false, responsive: true).healthy)
    }
}

@Suite struct ForecastTests {
    let settings = Config.ForecastSettings()

    func feed(_ s: inout ForecastState, _ points: [(Double, Int, PressureLevel)]) -> [(Forecast, Bool)] {
        points.map { Forecaster.update(&s, sample: sample($0.0, $0.2, available: $0.1), settings: settings) }
    }

    @Test func stableWhenFlat() {
        var s = ForecastState()
        let out = feed(&s, [(0, 60, .normal), (60, 60, .normal), (120, 60, .normal)])
        #expect(out.last!.0.stable && out.last!.0.etaWarning == nil)
        #expect(out.last!.0.summary == "stable")
    }

    @Test func etaFromFallingTrend() {
        var s = ForecastState()
        let out = feed(&s, [(0, 60, .normal), (60, 57, .normal), (120, 54, .normal), (180, 51, .normal)])
        let f = out.last!.0
        #expect(abs(f.etaWarning! - (51 - 25) / 3.0) < 0.5)
        #expect(f.etaWarningLow! <= f.etaWarning!)
        #expect(f.summary.contains("yellow in"))
        // The alarm is raised once, when the ETA first enters the 10-minute horizon.
        #expect(out.map(\.1) == [false, false, true, false])
    }

    @Test func alarmHitMissAndLearnedThreshold() {
        var s = ForecastState()
        _ = feed(&s, [(0, 40, .normal), (60, 34, .normal), (120, 28, .normal)])
        #expect(s.openAlarmAt != nil)
        _ = feed(&s, [(180, 22, .warning)])
        #expect(s.hitsTotal == 1 && s.leadTimesMinutes.count == 1)
        #expect(s.warningLevels == [22])
        _ = feed(&s, [(240, 10, .critical)])
        #expect(s.criticalLevels == [10])
        _ = feed(&s, [(300, 50, .normal), (360, 50, .normal), (420, 20, .warning)])
        #expect(s.missed == 1)
    }

    /// Adversarial: a false-alarm storm must switch forecast-driven actions off.
    @Test func falseAlarmStormDisarms() {
        var s = ForecastState()
        var t = 0.0
        for _ in 0..<6 {
            _ = feed(&s, [(t, 40, .normal), (t + 60, 30, .normal)])
            _ = feed(&s, [(t + 120, 45, .normal), (t + 2000, 45, .normal)])
            t += 4000
        }
        #expect(s.falseAlarmsTotal >= 5)
        #expect(s.armed == false)
        let (f, _) = Forecaster.update(&s, sample: sample(t, available: 45), settings: settings)
        #expect(f.armed == false)
    }

    @Test func alreadyBelowThreshold() {
        var s = ForecastState()
        let out = feed(&s, [(0, 20, .normal), (60, 19, .normal)])
        #expect(out.last!.0.etaWarning == 0)
    }
}

@Suite struct RegretTests {
    let settings = Config.RegretSettings()

    @Test func returnSoonIsRegret() {
        var s = RegretState()
        RegretTracker.recordFreeze(&s, appID: "a", at: 0, reliefMB: 500, dryRun: false)
        let r = RegretTracker.recordThaw(&s, appID: "a", at: 60, reason: Code.thawActivated, realizedReliefMB: 400, settings: settings)
        #expect(r == 0.3)
        #expect(s.records[0].regretted && s.records[0].realizedReliefMB == 400)
        RegretTracker.recordFreeze(&s, appID: "a", at: 1000, reliefMB: 500, dryRun: false)
        let r2 = RegretTracker.recordThaw(&s, appID: "a", at: 5000, reason: Code.thawActivated, realizedReliefMB: nil, settings: settings)
        #expect(r2 < 0.3)
        #expect(s.regretRate(since: 0) == (1, 2))
    }

    @Test func slowThawIsRegretAndUnknownAppIsNoop() {
        var s = RegretState()
        #expect(RegretTracker.recordThaw(&s, appID: "x", at: 0, reason: "", realizedReliefMB: nil, settings: settings) == 0)
        #expect(RegretTracker.recordLatency(&s, appID: "x", latencyMs: 1, at: 0, settings: settings) == 0)
        RegretTracker.recordFreeze(&s, appID: "a", at: 0, reliefMB: 500, dryRun: false)
        RegretTracker.recordThaw(&s, appID: "a", at: 9000, reason: Code.thawMaxDuration, realizedReliefMB: nil, settings: settings)
        #expect(s.perApp["a"] == 0)
        let r = RegretTracker.recordLatency(&s, appID: "a", latencyMs: 900, at: 9001, settings: settings)
        #expect(r == 0.3 && s.records[0].slowThaw)
    }

    /// Adversarial: the daily budget must not flap on and off within a day.
    @Test func dailyBudgetTurnsConservativeFor24h() {
        var s = RegretState()
        var c = settings
        c.dailyBudget = 2
        for i in 0..<3 {
            RegretTracker.recordFreeze(&s, appID: "a\(i)", at: Double(i * 10), reliefMB: 1, dryRun: false)
            RegretTracker.recordThaw(&s, appID: "a\(i)", at: Double(i * 10 + 5), reason: Code.thawActivated, realizedReliefMB: nil, settings: c)
        }
        #expect(s.isConservative(at: 100))
        #expect(s.isConservative(at: 86000))
        #expect(!s.isConservative(at: 25 + 86400))
    }

    @Test func thresholdsAndDemotion() {
        #expect(RegretTracker.adjustedIdle(current: 0, base: 15, regret: 0.4) == nil)
        #expect(RegretTracker.adjustedIdle(current: 0, base: 15, regret: 0.6) == 30)
        #expect(RegretTracker.adjustedIdle(current: 400, base: 15, regret: 0.6) == 480)
        #expect(!RegretTracker.shouldDemote(regret: 0.8))
        #expect(RegretTracker.shouldDemote(regret: 0.81))
    }

    @Test func recordsAreCapped() {
        var s = RegretState()
        for i in 0..<(RegretState.maxRecords + 5) { RegretTracker.recordFreeze(&s, appID: "a", at: Double(i), reliefMB: 1, dryRun: true) }
        #expect(s.records.count == RegretState.maxRecords)
    }
}

@Suite struct HabitTests {
    @Test func buckets() {
        #expect(HabitTable.bucket(weekday: 1, hour: 3) == "we-0")
        #expect(HabitTable.bucket(weekday: 4, hour: 13) == "wd-12")
        #expect(HabitTable.bucket(weekday: 7, hour: 23) == "we-18")
    }

    @Test func probabilitiesAndSupport() {
        var h = HabitTable()
        for _ in 0..<8 { h.record(from: "a", to: "b", bucket: "wd-6", day: 100) }
        for _ in 0..<2 { h.record(from: "a", to: "c", bucket: "wd-6", day: 100) }
        h.record(from: "a", to: "a", bucket: "wd-6", day: 100)  // self-transitions ignored
        let pb = h.probability(from: "a", to: "b", bucket: "wd-6")
        #expect(pb.support == 10)
        #expect(abs(pb.p - 8.5 / 11.5) < 1e-9)
        #expect(h.predict(from: "a", bucket: "wd-6").map(\.id) == ["b", "c"])
        #expect(h.predict(from: "a", bucket: "we-6").isEmpty)
        #expect(h.predict(from: "z", bucket: "wd-6").isEmpty)
    }

    /// Adversarial: one unusual day cannot dominate the table.
    @Test func dailyCapLimitsPoisoning() {
        var h = HabitTable()
        for _ in 0..<500 { h.record(from: "a", to: "odd", bucket: "wd-6", day: 1) }
        #expect(h.counts["wd-6"]?["a"]?["odd"] == Double(HabitTable.dailyCapPerPair))
        for d in 2...30 { for _ in 0..<5 { h.record(from: "a", to: "usual", bucket: "wd-6", day: d) } }
        #expect(h.predict(from: "a", bucket: "wd-6").first?.id == "usual")
    }

    @Test func decayForgetsOldHabits() {
        var h = HabitTable()
        h.record(from: "a", to: "b", bucket: "wd-6", day: 1)
        h.record(from: "x", to: "y", bucket: "wd-6", day: 400)
        #expect(h.counts["wd-6"]?["a"] == nil)
        #expect(h.counts["wd-6"]?["x"]?["y"] == 1)
    }

    @Test func offlineEvaluation() {
        var seq: [(time: Double, id: String, weekday: Int, hour: Int)] = []
        for i in 0..<60 {
            seq.append((Double(i * 120), "mail", 3, 9))
            seq.append((Double(i * 120 + 60), "editor", 3, 9))
        }
        let e = HabitEvaluation.run(activations: seq)
        #expect(e.predictions > 100)
        #expect(e.top1Rate! > 0.95)
        #expect(e.top3Rate! >= e.top1Rate!)
        #expect(HabitEvaluation().top1Rate == nil)
    }
}

@Suite struct GuardTests {
    let g = Config.GuardSettings()

    @Test func newRemoteConnectionIsActiveUntilQuiet() {
        var mem: [String: Double] = [:]
        let s = [SocketFact(kind: .tcp, established: true, localPort: 50000, remotePort: 443, key: "c1")]
        #expect(Guards.connection(s, firstSeen: &mem, now: 0, settings: g).active)
        #expect(Guards.connection(s, firstSeen: &mem, now: 60, settings: g).active)
        #expect(!Guards.connection(s, firstSeen: &mem, now: 200, settings: g).active)
        // Queued data means traffic right now.
        var busy = s
        busy[0].queuedBytes = 10
        #expect(Guards.connection(busy, firstSeen: &mem, now: 300, settings: g).active)
        // Keys that disappear are forgotten.
        _ = Guards.connection([], firstSeen: &mem, now: 400, settings: g)
        #expect(mem.isEmpty)
    }

    @Test func loopbackAndBenignPortsAreIgnored() {
        var mem: [String: Double] = [:]
        let s = [SocketFact(kind: .tcp, established: true, remotePort: 5223, key: "push"),
                 SocketFact(kind: .tcp, established: true, remotePort: 9000, remoteIsLoopback: true, key: "lo"),
                 SocketFact(kind: .udp, remotePort: 443, key: "quic")]
        #expect(!Guards.connection(s, firstSeen: &mem, now: 0, settings: g).active)
    }

    @Test func servingListener() {
        var mem: [String: Double] = [:]
        let listen = SocketFact(kind: .tcp, listening: true, localPort: 3000, key: "l")
        #expect(!Guards.connection([listen], firstSeen: &mem, now: 0, settings: g).serving)
        let client = SocketFact(kind: .tcp, established: true, localPort: 3000, remotePort: 51000, remoteIsLoopback: true, key: "c")
        #expect(Guards.connection([listen, client], firstSeen: &mem, now: 0, settings: g).serving)
    }

    @Test func writes() {
        func w(_ name: String, _ writing: Bool, _ age: Double) -> (Bool, Bool) {
            let r = Guards.writes([FileFact(name: name, openForWriting: writing, secondsSinceModified: age)], settings: g)
            return (r.recentWrite, r.lockHeld)
        }
        #expect(w("index.lock", true, 9999) == (false, true))
        #expect(w("index.lock", false, 1) == (false, false))
        #expect(w("History-journal", false, 5) == (false, true))
        #expect(w("History-wal", true, 9999) == (false, false))
        #expect(w("draft.txt", true, 5) == (true, false))
        #expect(w("draft.txt", true, 500) == (false, false))
        #expect(w("draft.txt", false, 5) == (false, false))
        #expect(w("LOCK", true, 1) == (false, false))
        #expect(w("app.log", true, 1) == (false, false))
    }
}

@Suite struct RunawayTests {
    let settings = Config.RunawaySettings()

    @Test func sustainedCPUInBackground() {
        var s = RunawayState()
        var last: [RunawayFinding] = []
        for t in stride(from: 0.0, through: 300, by: 30) {
            last = Runaway.update(&s, apps: [app("com.hot", cpu: 95)], now: t, settings: settings).current
        }
        #expect(last.map(\.code) == [Code.runawayCPU])
        var s2 = RunawayState()
        for t in stride(from: 0.0, through: 300, by: 30) {
            last = Runaway.update(&s2, apps: [app("com.hot", cpu: t == 150 ? 10 : 95)], now: t, settings: settings).current
        }
        #expect(last.isEmpty)
    }

    @Test func steadyGrowthButNotNoise() {
        var s = RunawayState()
        var out: [RunawayFinding] = []
        for (i, t) in stride(from: 0.0, through: 600, by: 60).enumerated() {
            out = Runaway.update(&s, apps: [app("com.leak", mb: 1000 + Double(i) * 100)], now: t, settings: settings).current
        }
        #expect(out.map(\.code) == [Code.runawayMemory])
        var n = RunawayState()
        for (i, t) in stride(from: 0.0, through: 600, by: 60).enumerated() {
            out = Runaway.update(&n, apps: [app("com.noisy", mb: i % 2 == 0 ? 1000 : 3000)], now: t, settings: settings).current
        }
        #expect(out.isEmpty)
    }

    @Test func notificationsAreRateLimitedAndProtectedIgnored() {
        var s = RunawayState()
        var notes = 0
        for t in stride(from: 0.0, through: 7 * 3600, by: 60) {
            notes += Runaway.update(&s, apps: [app("com.hot", cpu: 99), app("com.apple.Terminal", cpu: 99)], now: t, settings: settings).notify.count
        }
        #expect(notes == 2)  // at ~5 min and again after 6 h
        #expect(s.series["com.apple.Terminal"] == nil)
        _ = Runaway.update(&s, apps: [], now: 8 * 3600, settings: settings)
        #expect(s.series.isEmpty)
    }

    @Test func linearFit() {
        #expect(Runaway.linearFit([(0, 1)]) == nil)
        #expect(Runaway.linearFit([(1, 1), (1, 2)]) == nil)
        let f = Runaway.linearFit([(0, 0), (1, 2), (2, 4)])!
        #expect(f.slope == 2 && f.r2 == 1)
        #expect(Runaway.linearFit([(0, 5), (1, 5)])!.r2 == 1)
    }
}

@Suite struct StagedThawTests {
    @Test func orderAndDelays() {
        let plan = StagedThaw.schedule([ThawCandidate(appID: "old", reclaimedMB: 1000, priority: 1),
                                        ThawCandidate(appID: "new", reclaimedMB: 500, priority: 9),
                                        ThawCandidate(appID: "mid", reclaimedMB: 100_000, priority: 5)], swapInMBps: 1000)
        #expect(plan.map(\.appID) == ["new", "mid", "old"])
        #expect(plan.map(\.delay) == [0, 0.5, 10])
        #expect(StagedThaw.schedule([], swapInMBps: 1).isEmpty)
    }
}

@Suite struct ProfileTests {
    @Test func selection() {
        var p = Config.ProfileSettings()
        let s = sample(0)
        #expect(activeProfile(settings: p, session: SessionContext(), sample: s, weekday: 2, hour: 10) == .work)
        #expect(activeProfile(settings: p, session: SessionContext(), sample: sample(0, onBattery: true), weekday: 2, hour: 10) == .batterySaver)
        #expect(activeProfile(settings: p, session: SessionContext(displayMirrored: true), sample: s, weekday: 2, hour: 10) == .presentation)
        p.schedule = [ScheduleRule(weekdays: [2], startHour: 9, endHour: 18, profile: .dev)]
        #expect(activeProfile(settings: p, session: SessionContext(), sample: s, weekday: 2, hour: 10) == .dev)
        #expect(activeProfile(settings: p, session: SessionContext(), sample: s, weekday: 3, hour: 10) == .work)
        p.manual = .batterySaver
        #expect(activeProfile(settings: p, session: SessionContext(screenSharing: true), sample: s, weekday: 2, hour: 10) == .batterySaver)
    }

    @Test func deltas() {
        let base = Config()
        #expect(effectiveConfig(base, hardware: Hardware(memoryGB: 8), profile: .work).idleMinutes < base.idleMinutes)
        #expect(effectiveConfig(base, hardware: Hardware(memoryGB: 16), profile: .work) == base)
        #expect(effectiveConfig(base, hardware: Hardware(memoryGB: 64), profile: .work).idleMinutes > base.idleMinutes)
        let hdd = effectiveConfig(base, hardware: Hardware(memoryGB: 16, rotationalDisk: true), profile: .work)
        #expect(hdd.maxFrozenApps == 3 && hdd.reliefTargetWarningMB == 512)
        let batt = effectiveConfig(base, hardware: hw16, profile: .batterySaver)
        #expect(batt.idleMinutes < base.idleMinutes && batt.runaway.cpuMinutes == 2)
        #expect(effectiveConfig(base, hardware: hw16, profile: .dev).idleMinutes > base.idleMinutes)
        // Safety settings never move.
        for p in ProfileName.allCases {
            let c = effectiveConfig(base, hardware: Hardware(memoryGB: 4, rotationalDisk: true), profile: p)
            #expect(c.maxFrozenMinutes == base.maxFrozenMinutes && c.deny == base.deny && c.guards == base.guards)
        }
        #expect(RAMProfile(memoryGB: 8) == .small && RAMProfile(memoryGB: 18) == .balanced && RAMProfile(memoryGB: 32) == .large)
        #expect(profileAllowsAction(Hardware(memoryGB: 8), level: .warning))
        #expect(!profileAllowsAction(Hardware(memoryGB: 8), level: .normal))
    }
}
