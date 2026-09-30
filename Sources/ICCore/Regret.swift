/// S2 Regret-aware decisions: every freeze becomes a record with its benefit,
/// cost and a regret flag. Regret feeds back into per-app thresholds and a global
/// daily budget.
public struct FreezeRecord: Codable, Equatable, Sendable {
    public var appID: String
    public var frozenAt: Double
    public var reliefEstimateMB: Double
    public var realizedReliefMB: Double?
    public var thawedAt: Double?
    public var thawReason: String?
    public var thawLatencyMs: Double?
    public var returnedSoon = false
    public var dryRun: Bool

    public var regretted: Bool { returnedSoon || slowThaw }
    public var slowThaw = false
}

public struct RegretState: Codable, Equatable, Sendable {
    public var records: [FreezeRecord] = []
    /// Per-app EWMA of the regret flag.
    public var perApp: [String: Double] = [:]
    public var conservativeUntil: Double?
    public init() {}

    static let maxRecords = 2000
    static let alpha = 0.3

    public func isConservative(at now: Double) -> Bool { (conservativeUntil ?? 0) > now }

    public func regretRate(since: Double) -> (regretted: Int, total: Int) {
        let closed = records.filter { ($0.thawedAt ?? -1) >= since }
        return (closed.filter(\.regretted).count, closed.count)
    }
}

public enum RegretTracker {
    public static func recordFreeze(_ s: inout RegretState, appID: String, at: Double, reliefMB: Double, dryRun: Bool) {
        s.records.append(FreezeRecord(appID: appID, frozenAt: at, reliefEstimateMB: reliefMB, dryRun: dryRun))
        if s.records.count > RegretState.maxRecords { s.records.removeFirst(s.records.count - RegretState.maxRecords) }
    }

    /// Closes the open record for `appID`. Returns the per-app regret EWMA after the update.
    @discardableResult
    public static func recordThaw(_ s: inout RegretState, appID: String, at: Double, reason: String,
                                  realizedReliefMB: Double?, settings: Config.RegretSettings) -> Double {
        guard let i = s.records.lastIndex(where: { $0.appID == appID && $0.thawedAt == nil }) else {
            return s.perApp[appID] ?? 0
        }
        s.records[i].thawedAt = at
        s.records[i].thawReason = reason
        s.records[i].realizedReliefMB = realizedReliefMB
        s.records[i].returnedSoon = reason == Code.thawActivated
            && at - s.records[i].frozenAt < settings.returnWindowMinutes * 60
        return update(&s, index: i, at: at, settings: settings)
    }

    /// Adds the measured thaw latency to the most recent closed record for `appID`.
    @discardableResult
    public static func recordLatency(_ s: inout RegretState, appID: String, latencyMs: Double, at: Double,
                                     settings: Config.RegretSettings) -> Double {
        guard let i = s.records.lastIndex(where: { $0.appID == appID && $0.thawedAt != nil }) else {
            return s.perApp[appID] ?? 0
        }
        let wasRegretted = s.records[i].regretted
        s.records[i].thawLatencyMs = latencyMs
        s.records[i].slowThaw = latencyMs > settings.thawLatencyBudgetMs
        // Only re-score when the flag flipped; the thaw already counted once.
        if !wasRegretted && s.records[i].regretted {
            s.perApp[appID] = (s.perApp[appID] ?? 0) + RegretState.alpha * (1 - (s.perApp[appID] ?? 0))
            checkBudget(&s, at: at, settings: settings)
        }
        return s.perApp[appID] ?? 0
    }

    private static func update(_ s: inout RegretState, index i: Int, at: Double, settings: Config.RegretSettings) -> Double {
        let r = s.records[i]
        let old = s.perApp[r.appID] ?? 0
        let new = old + RegretState.alpha * ((r.regretted ? 1 : 0) - old)
        s.perApp[r.appID] = new
        checkBudget(&s, at: at, settings: settings)
        return new
    }

    private static func checkBudget(_ s: inout RegretState, at: Double, settings: Config.RegretSettings) {
        let day = s.records.filter { ($0.thawedAt ?? 0) > at - 86400 && $0.regretted }.count
        if day > settings.dailyBudget {
            s.conservativeUntil = at + 86400
        }
    }

    /// Learned idle threshold after a regret update: doubles when the app's regret
    /// is high, capped at 8 h. Returns nil when no change is needed.
    public static func adjustedIdle(current: Double, base: Double, regret: Double) -> Double? {
        guard regret > 0.5 else { return nil }
        return min(max(current, base) * 2, 480)
    }

    /// Demote to Tier S when regret stays very high.
    public static func shouldDemote(regret: Double) -> Bool { regret > 0.8 }
}
