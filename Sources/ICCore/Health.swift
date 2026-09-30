import Foundation

/// Mac Health score, 0-100. The formula is deliberately simple and documented in
/// docs/ARCHITECTURE.md; every penalty is listed so the number can be explained.
public struct HealthScore: Codable, Equatable, Sendable {
    public var score: Int
    public var band: Band
    public var penalties: [Penalty]

    public enum Band: String, Codable, Sendable { case good, fair, poor }

    public struct Penalty: Codable, Equatable, Sendable {
        public var reason: String
        public var points: Int
    }
}

public enum Health {
    /// - Parameters:
    ///   - sample: the latest reading.
    ///   - swapOutMBPerMinute: swap-out rate over the last few minutes.
    ///   - runawayApps: apps the runaway guard currently flags.
    public static func score(_ sample: SystemSample, swapOutMBPerMinute: Double, runawayApps: Int) -> HealthScore {
        var p: [HealthScore.Penalty] = []
        func add(_ reason: String, _ points: Int) { if points > 0 { p.append(.init(reason: reason, points: points)) } }

        switch sample.pressure {
        case .normal: break
        case .warning: add("memory pressure warning", 25)
        case .critical: add("memory pressure critical", 50)
        }
        add("swapping out", Int(min(15, swapOutMBPerMinute / 10).rounded()))
        let compressedShare = sample.compressedMB / max(sample.physicalMB, 1)
        add("large compressed memory", compressedShare > 0.25 ? Int(min(10, (compressedShare - 0.25) * 40).rounded()) : 0)
        switch sample.thermal {
        case .nominal: break
        case .fair: add("warm (thermal fair)", 5)
        case .serious: add("thermal throttling (serious)", 15)
        case .critical: add("thermal throttling (critical)", 30)
        }
        add("low free disk", sample.freeDiskGB < 5 ? 20 : sample.freeDiskGB < 10 ? 10 : 0)
        add("runaway apps", min(20, runawayApps * 10))

        let score = max(0, 100 - p.map(\.points).reduce(0, +))
        return HealthScore(score: score, band: score >= 80 ? .good : score >= 50 ? .fair : .poor, penalties: p)
    }

    /// Swap-out rate from two samples (pages -> MB per minute).
    public static func swapOutRate(_ a: SystemSample, _ b: SystemSample, pageKB: Double = 16) -> Double {
        guard b.time > a.time, b.swapOuts >= a.swapOuts else { return 0 }
        return Double(b.swapOuts - a.swapOuts) * pageKB / 1024 / ((b.time - a.time) / 60)
    }
}

// MARK: - S5 post-thaw health

/// What the daemon saw after thawing an app.
public struct ThawOutcome: Codable, Equatable, Sendable {
    /// Every process of the tree still exists.
    public var alive: Bool
    /// Result of the responsiveness probe; `nil` when no probe was possible.
    public var responsive: Bool?

    public init(alive: Bool, responsive: Bool?) {
        self.alive = alive
        self.responsive = responsive
    }

    public var healthy: Bool { alive && responsive != false }
}

public struct QuarantineEntry: Codable, Equatable, Sendable {
    public var appID: String
    public var name: String
    public var at: Double
    public var reason: String
}
