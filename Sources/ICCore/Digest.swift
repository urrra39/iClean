import Foundation

/// Per-app usage kept for suggestions: how often an app sat idle in the background
/// and how much memory it held. Counts only.
public struct AppUsage: Codable, Equatable, Sendable {
    public var name: String
    public var samples = 0
    public var idleSamples = 0
    public var residentSumMB = 0.0
    public var since: Double

    public var idleShare: Double { samples > 0 ? Double(idleSamples) / Double(samples) : 0 }
    public var averageMB: Double { samples > 0 ? residentSumMB / Double(samples) : 0 }
}

public enum Usage {
    /// Adds one tick. Counts are halved every 7 days so the window stays about a week.
    public static func update(_ u: inout [String: AppUsage], apps: [AppSnapshot], now: Double) {
        for app in apps where app.isRegularApp && !Protection.isProtected(app) {
            var x = u[app.id] ?? AppUsage(name: app.name, since: now)
            if now - x.since > 7 * 86400 {
                x.samples /= 2
                x.idleSamples /= 2
                x.residentSumMB /= 2
                x.since = now - 3.5 * 86400
            }
            x.samples += 1
            if !app.isFrontmost && !app.hasVisibleWindow { x.idleSamples += 1 }
            x.residentSumMB += app.residentMB
            x.name = app.name
            u[app.id] = x
        }
    }
}

public struct Suggestion: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case allow, deny }
    public var kind: Kind
    public var appID: String
    public var text: String
}

/// The daily/weekly digest (Day Reciprocity): only measured, locally stored data.
public struct Digest: Codable, Equatable, Sendable {
    public var days: Int
    public var observeMinutes: [String: Double]
    public var activeMinutes: [String: Double]
    public var freezes: Int
    public var wouldFreeze: Int
    public var thaws: Int
    public var thawP50Ms: Double?
    public var thawP95Ms: Double?
    public var reliefAvgMB: Double?
    public var cpuSecondsSavedEstimate: Double
    public var regretted: Int
    public var closedFreezes: Int
    public var forecastHits: Int
    public var forecastFalseAlarms: Int
    public var forecastMissed: Int
    public var forecastArmed: Bool
    public var forecastLeadP50Minutes: Double?
    public var guardSaves: [String: Int]
    public var quarantined: [String]
    public var suggestions: [Suggestion]
    public var healthyIdle: Bool

    public var text: String {
        func mins(_ d: [String: Double], _ level: String) -> String { String(format: "%.0f", d[level] ?? 0) }
        var l: [String] = []
        l.append("Last \(days) day\(days == 1 ? "" : "s"):")
        if healthyIdle { l.append("  Your Mac is healthy; iClear is idle.") }
        l.append(
            "  Minutes in yellow/red pressure: Observe \(mins(observeMinutes, "warning"))/\(mins(observeMinutes, "critical")), Active \(mins(activeMinutes, "warning"))/\(mins(activeMinutes, "critical"))"
        )
        l.append("  Apps frozen: \(freezes), thawed: \(thaws), would have frozen (Observe): \(wouldFreeze)")
        l.append(
            "  Thaw latency: "
                + (thawP50Ms.map { p50 in String(format: "p50 %.1f ms, p95 %.1f ms", p50, thawP95Ms ?? p50) } ?? "not enough data"))
        l.append(
            "  Memory reclaimed per freeze (measured, resident): "
                + (reliefAvgMB.map { String(format: "%.0f MB average", $0) } ?? "not enough data"))
        l.append(
            String(format: "  CPU time not spent by frozen apps: %.0f s (estimate from CPU use at freeze time)", cpuSecondsSavedEstimate))
        l.append(
            "  Regret rate (S2): "
                + (closedFreezes > 0
                    ? String(
                        format: "%d of %d freezes regretted (%.0f%%)", regretted, closedFreezes,
                        100 * Double(regretted) / Double(closedFreezes))
                    : "not enough data"))
        let alarms = forecastHits + forecastFalseAlarms
        l.append(
            "  Forecast (S1): "
                + (alarms + forecastMissed > 0
                    ? "\(forecastHits) hits, \(forecastFalseAlarms) false alarms, \(forecastMissed) missed"
                        + (forecastLeadP50Minutes.map { String(format: ", median lead %.1f min", $0) } ?? "")
                        + (forecastArmed ? "" : " (forecast-driven actions switched off: too many false alarms)")
                    : "not enough data"))
        let saves = guardSaves.values.reduce(0, +)
        l.append(
            "  Guard saves (S4): "
                + (saves > 0
                    ? guardSaves.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                    : "none"))
        l.append("  Quarantined apps (S5): " + (quarantined.isEmpty ? "none" : quarantined.joined(separator: ", ")))
        for s in suggestions { l.append("  Suggestion: \(s.text)") }
        return l.joined(separator: "\n")
    }
}

public enum DigestBuilder {
    public static func build(state: EngineState, config: Config, now: Double, days: Int) -> Digest {
        let today = Int(now / 86400)
        let range = (today - days + 1)...today
        let ds = state.days.filter { range.contains(Int($0.key) ?? -1) }.map(\.value)
        func minutes(_ mode: String) -> [String: Double] {
            var m: [String: Double] = [:]
            for d in ds {
                for (k, v) in d.pressureSeconds where k.hasPrefix(mode + ".") {
                    m[String(k.dropFirst(mode.count + 1)), default: 0] += v / 60
                }
            }
            return m
        }
        let lat = ds.flatMap(\.thawLatenciesMs)
        let relief = ds.flatMap(\.realizedReliefMB)
        var saves: [String: Int] = [:]
        for d in ds { for (k, v) in d.guardSaves { saves[k, default: 0] += v } }
        let regret = state.regret.regretRate(since: Double(range.lowerBound) * 86400)
        let f = state.forecast
        let obs = minutes("observe")
        let act = minutes("active")
        let yellowRed = (obs["warning"] ?? 0) + (obs["critical"] ?? 0) + (act["warning"] ?? 0) + (act["critical"] ?? 0)
        return Digest(
            days: days, observeMinutes: obs, activeMinutes: act,
            freezes: ds.map(\.freezes).reduce(0, +), wouldFreeze: ds.map(\.wouldFreeze).reduce(0, +),
            thaws: ds.map(\.thaws).reduce(0, +),
            thawP50Ms: percentile(lat, 0.5), thawP95Ms: percentile(lat, 0.95),
            reliefAvgMB: relief.isEmpty ? nil : relief.reduce(0, +) / Double(relief.count),
            cpuSecondsSavedEstimate: ds.map(\.cpuSecondsSavedEstimate).reduce(0, +),
            regretted: regret.regretted, closedFreezes: regret.total,
            forecastHits: f.hitsTotal, forecastFalseAlarms: f.falseAlarmsTotal, forecastMissed: f.missed,
            forecastArmed: f.armed, forecastLeadP50Minutes: percentile(f.leadTimesMinutes, 0.5),
            guardSaves: saves, quarantined: state.quarantine.values.map(\.name).sorted(),
            suggestions: suggestions(state: state, config: config, now: now),
            healthyIdle: yellowRed == 0 && state.frozen.isEmpty)
    }

    /// "Figma was idle 92% of the week and uses 1.4 GB: add to auto-freeze?" and
    /// "Slack was frozen and you reopened it 3 times within a minute: exclude it?"
    public static func suggestions(state: EngineState, config: Config, now: Double) -> [Suggestion] {
        let usage = state.usage
        var out: [Suggestion] = []
        for (id, u) in usage.sorted(by: { $0.key < $1.key }) where u.samples >= 60 && u.idleShare >= 0.9 && u.averageMB >= 500 {
            let tier = Protection.tier(for: id, config: config)
            guard tier != .auto, !Protection.isProtectedID(id), !config.allow.contains(id), !config.deny.contains(id) else { continue }
            out.append(
                Suggestion(
                    kind: .allow, appID: id,
                    text: String(
                        format: "%@ was idle %.0f%% of the time and uses %@: add to auto-freeze? (iclear config allow %@)",
                        u.name, u.idleShare * 100, mb(u.averageMB), id)))
        }
        let week = now - 7 * 86400
        var soon: [String: Int] = [:]
        for r in state.regret.records where r.returnedSoon && r.frozenAt >= week && r.thawedAt.map({ $0 - r.frozenAt < 60 }) == true {
            soon[r.appID, default: 0] += 1
        }
        for (id, n) in soon.sorted(by: { $0.key < $1.key }) where n >= 3 && !config.deny.contains(id) {
            let name = usage[id]?.name ?? id
            out.append(
                Suggestion(
                    kind: .deny, appID: id,
                    text: "\(name) was frozen and you reopened it \(n) times within a minute: exclude it? (iclear config deny \(id))"))
        }
        return out
    }
}

// MARK: - S8 RAM right-sizing advisor

public struct Advice: Codable, Equatable, Sendable {
    public var enoughData: Bool
    public var daysOfData: Int
    public var p50WorkingSetGB: Double?
    public var p95WorkingSetGB: Double?
    public var minutesYellowRed: Double
    public var swapChurnMinutes: Int
    public var comfortableLowGB: Int?
    public var comfortableHighGB: Int?
    public var text: String
}

public enum Advisor {
    public static let minDays = 7
    public static let minSamplesPerDay = 60
    static let sizes = [8, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192]

    public static func advise(days: [DayStats], physicalGB: Double) -> Advice {
        let usable = days.filter { $0.workingSetMB.count >= minSamplesPerDay }
        let yr =
            usable.flatMap { $0.pressureSeconds.filter { $0.key.hasSuffix(".warning") || $0.key.hasSuffix(".critical") }.map(\.value) }
            .reduce(0, +) / 60
        let churn = usable.map(\.swapChurnMinutes).reduce(0, +)
        guard usable.count >= minDays else {
            return Advice(
                enoughData: false, daysOfData: usable.count, minutesYellowRed: yr, swapChurnMinutes: churn,
                text:
                    "Not enough data: \(usable.count) of \(minDays) days with at least \(minSamplesPerDay) minutes of samples. iClear will not guess."
            )
        }
        let ws = usable.flatMap(\.workingSetMB).map { $0 / 1024 }
        let p50 = percentile(ws, 0.5)!
        let p90 = percentile(ws, 0.9)!
        let p95 = percentile(ws, 0.95)!
        let p99 = percentile(ws, 0.99)!
        // 25% headroom for file cache and bursts, rounded up to sizes Macs ship with.
        func round(_ gb: Double) -> Int { sizes.first { Double($0) >= gb * 1.25 } ?? sizes.last! }
        let low = round(p90)
        let high = round(p99)
        var text = String(
            format: """
                ESTIMATE from %d days of local history (method: 90th-99th percentile of used memory + 25%% headroom).
                Used memory: median %.1f GB, 95th percentile %.1f GB. Minutes in yellow/red: %.0f. Minutes with heavy swapping: %d.
                This workload would likely be comfortable with %d-%d GB.
                """, usable.count, p50, p95, yr, churn, low, high)
        if Double(high) <= physicalGB && yr < 1 {
            text += "\nYour current \(Int(physicalGB)) GB appears sufficient for it."
        }
        return Advice(
            enoughData: true, daysOfData: usable.count, p50WorkingSetGB: p50, p95WorkingSetGB: p95,
            minutesYellowRed: yr, swapChurnMinutes: churn, comfortableLowGB: low, comfortableHighGB: high, text: text)
    }

    /// Holdout check: learn the "comfortable" threshold on the first days, then test
    /// whether days above it are the days that saw yellow/red pressure.
    public static func holdout(days: [DayStats]) -> (agreement: Double, testDays: Int)? {
        let usable = days.filter { $0.workingSetMB.count >= minSamplesPerDay }
        guard usable.count >= minDays * 2 else { return nil }
        let split = usable.count * 2 / 3
        let train = usable.prefix(split)
        let test = usable.suffix(from: split)
        guard let threshold = percentile(train.flatMap(\.workingSetMB), 0.95) else { return nil }
        let agree = test.filter { d in
            let above = (percentile(d.workingSetMB, 0.95) ?? 0) > threshold
            let pressured = d.pressureSeconds.contains { ($0.key.hasSuffix(".warning") || $0.key.hasSuffix(".critical")) && $0.value > 60 }
            return above == pressured
        }.count
        return (Double(agree) / Double(test.count), test.count)
    }
}
