/// S7 staged thaw: when several apps must thaw at once, thaw the most urgent first
/// and space the rest by how long their memory takes to fault back in.
public struct ThawCandidate: Equatable, Sendable {
    public var appID: String
    /// Memory expected to be faulted back in (resident at freeze minus resident now).
    public var reclaimedMB: Double
    /// Higher thaws first (for example the app being activated, then most recently used).
    public var priority: Double

    public init(appID: String, reclaimedMB: Double, priority: Double) {
        self.appID = appID
        self.reclaimedMB = reclaimedMB
        self.priority = priority
    }
}

public enum StagedThaw {
    /// Delay in seconds before each app is thawed. The first app always has delay 0.
    /// `swapInMBps` is the measured fault-in throughput; delays are capped so the last
    /// app never waits more than `maxTotalSeconds`.
    public static func schedule(_ apps: [ThawCandidate], swapInMBps: Double,
                                maxTotalSeconds: Double = 10) -> [(appID: String, delay: Double)] {
        let ordered = apps.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.appID < $1.appID }
        var out: [(String, Double)] = []
        var t = 0.0
        for a in ordered {
            out.append((a.appID, min(t, maxTotalSeconds)))
            t += max(0, a.reclaimedMB) / max(swapInMBps, 1)
        }
        return out.map { (appID: $0.0, delay: $0.1) }
    }
}
