import Foundation
import Testing

@testable import ICCore

@Suite struct ConfigTests {
    func load(_ json: String) throws -> (Config, [ConfigIssue]) {
        try Config.load(json: Data(json.utf8))
    }

    @Test func defaultsAreValidAndObserveFirst() {
        let c = Config()
        #expect(c.validate().isEmpty)
        #expect(c.mode == .observe)
        #expect(c.predictiveThaw == false)
        #expect(c.habits.preThaw == false)
        #expect(c.forecast.enabled == false)
    }

    @Test func missingKeysTakeDefaults() throws {
        let (c, issues) = try load(#"{"idleMinutes": 30, "guards": {"writeWindowSeconds": 10}}"#)
        #expect(c.idleMinutes == 30)
        #expect(c.guards.writeWindowSeconds == 10)
        #expect(c.guards.connections == true)
        #expect(c.maxFrozenMinutes == 240)
        #expect(issues.isEmpty)
    }

    @Test func roundTrip() throws {
        var c = Config()
        c.allow = ["com.figma.Desktop"]
        c.tiers = ["com.example.app": .optIn]
        c.wakeWindows = ["com.tinyspeck.slackmacgap": WakeWindow(thawSeconds: 30, everyMinutes: 10)]
        c.workspaces = ["Client A": ["com.figma.Desktop", "com.google.Chrome"]]
        c.profiles.manual = .dev
        c.profiles.schedule = [ScheduleRule(weekdays: [2, 3], startHour: 9, endHour: 17, profile: .work)]
        let (back, _) = try Config.load(json: c.encoded())
        #expect(back == c)
    }

    @Test func unknownKeysAreErrors() {
        #expect(throws: ConfigError.self) { try load(#"{"idleMinuts": 30}"#) }
        #expect(throws: ConfigError.self) { try load(#"{"guards": {"conections": false}}"#) }
    }

    @Test func mapsAcceptArbitraryKeys() throws {
        let (c, _) = try load(#"{"tiers": {"com.a.b": "B"}, "workspaces": {"X": ["com.a.b"]}}"#)
        #expect(c.tiers["com.a.b"] == .optIn)
        #expect(c.workspaces["X"] == ["com.a.b"])
    }

    @Test func malformedInputIsRejected() {
        #expect(throws: ConfigError.self) { try load("not json") }
        #expect(throws: ConfigError.self) { try load("[1, 2]") }
        #expect(throws: ConfigError.self) { try load(#"{"idleMinutes": "soon"}"#) }
        #expect(throws: ConfigError.self) { try load(#"{"mode": "aggressive"}"#) }
    }

    @Test(arguments: [
        #"{"idleMinutes": 0}"#, #"{"maxFrozenMinutes": 5000}"#, #"{"minFrozenMinutes": 300}"#,
        #"{"maxFrozenApps": 0}"#, #"{"maxFrozenPercentOfRAM": 95}"#, #"{"lowBatteryPercent": 90}"#,
        #"{"reliefTargetWarningMB": 3000}"#, #"{"forecast": {"horizonMinutes": 0}}"#,
        #"{"forecast": {"falseAlarmBudget": 2}}"#, #"{"trace": {"maxMB": 0}}"#, #"{"trace": {"retentionDays": 0}}"#,
        #"{"wakeWindows": {"com.a.b": {"thawSeconds": 700, "everyMinutes": 10}}}"#,
        #"{"profiles": {"schedule": [{"weekdays": [9], "startHour": 9, "endHour": 17, "profile": "work"}]}}"#,
        #"{"allow": ["not a bundle id"]}"#, #"{"version": 2}"#, #"{"guards": {"benignRemotePorts": [0]}}"#,
        #"{"regret": {"returnWindowMinutes": 0}}"#, #"{"runaway": {"cpuPercent": 0}}"#,
        #"{"cooldownMinutes": -1}"#, #"{"thawAfterNormalMinutes": 0}"#, #"{"idleCPUPercent": 101}"#,
        #"{"habits": {"preThawProbability": 1.5}}"#, #"{"guards": {"writeWindowSeconds": 0}}"#,
        #"{"healthCheck": {"probeTimeoutMs": 0}}"#, #"{"notifications": {"maxPerHour": -1}}"#,
        #"{"forecast": {"minAlarmsToJudge": 0}}"#, #"{"regret": {"thawLatencyBudgetMs": 0}}"#,
        #"{"regret": {"dailyBudget": -1}}"#,
    ])
    func invalidValuesAreErrors(json: String) {
        #expect(throws: ConfigError.self) { try load(json) }
    }

    @Test func conflictsAndProtectedRulesAreWarnings() throws {
        let (_, issues) = try load(#"{"allow": ["com.a.b", "com.apple.Terminal"], "deny": ["com.a.b"]}"#)
        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.severity == .warning })
        #expect(issues.map(\.description).joined().contains("deny wins"))
        #expect(issues.map(\.description).joined().contains("protected"))
    }

    @Test func errorDescriptionNamesThePath() {
        do {
            _ = try load(#"{"idleMinutes": 0}"#)
            Issue.record("expected an error")
        } catch let e as ConfigError {
            #expect(e.description.contains("idleMinutes"))
        } catch {
            Issue.record("wrong error \(error)")
        }
    }
}
