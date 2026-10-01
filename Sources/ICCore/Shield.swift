import Foundation

/// Foreground Shield: one adaptive ladder shared by Call Mode, the thermal trigger and
/// Anti-Beachball. It escalates only while interference is measured, steps down as soon
/// as it clears, and disarms itself when escalating does not measurably help.
public enum ShieldTrigger: String, Codable, CaseIterable, Sendable {
    case call, thermal, stall
}

public enum ShieldLevel: Int, Codable, Comparable, Sendable {
    /// Nothing changed.
    case off = 0
    /// Other user processes in the Darwin background band (CPU and disk throttled).
    case background = 1
    /// Eligible idle background apps paused as well.
    case pause = 2

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct ShieldSettings: Codable, Equatable, Sendable {
    /// Ship rule (docs/RELEASE_CRITERIA.md C8): off until paired runs show a benefit.
    public var enabled = false
    /// Interference (probe lateness p99, ms) above which the ladder climbs.
    public var interferenceMs = 2.0
    /// Highest step allowed.
    public var maxLevel = ShieldLevel.pause
    /// Escalations judged before deciding whether the ladder helps on this Mac.
    public var judgeAfter = 5
    /// Minimum median relative improvement of interference after escalating.
    public var minImprovement = 0.2
    public init() {}
}

public struct ShieldState: Codable, Equatable, Sendable {
    public var level = ShieldLevel.off
    public var active = false
    /// Consecutive samples above the threshold.
    public var strikes = 0
    /// Interference just before the last escalation, waiting for its "after" sample.
    public var pendingBefore: Double?
    /// Relative improvements of past escalations (0.3 = 30% less interference).
    public var improvements: [Double] = []
    public var disarmed = false
    public var message: String?
    public init() {}
}

public enum Shield {
    /// One step of the ladder. `interference` is the measured probe lateness p99 (ms) or
    /// nil when nothing was measured. Returns the level to apply now.
    public static func step(_ s: inout ShieldState, triggerActive: Bool, interference: Double?, settings: ShieldSettings) -> ShieldLevel {
        guard settings.enabled, triggerActive, !s.disarmed else {
            s.active = triggerActive
            s.strikes = 0
            s.pendingBefore = nil
            s.level = .off
            return .off
        }
        s.active = true
        // Score the last escalation with the first sample after it.
        if let before = s.pendingBefore, let now = interference {
            s.improvements = Array((s.improvements + [(before - now) / max(before, 0.001)]).suffix(20))
            s.pendingBefore = nil
            if s.improvements.count >= settings.judgeAfter {
                let sorted = s.improvements.sorted()
                if sorted[sorted.count / 2] < settings.minImprovement {
                    s.disarmed = true
                    s.message = String(
                        format: "Shield switched itself off: escalating cut interference by a median of %.0f%% on this Mac (needs %.0f%%).",
                        sorted[sorted.count / 2] * 100, settings.minImprovement * 100)
                    s.level = .off
                    return .off
                }
            }
        }
        guard let i = interference else { return s.level }
        if i > settings.interferenceMs {
            s.strikes += 1
            if s.strikes >= 2, s.level < settings.maxLevel {
                s.level = ShieldLevel(rawValue: s.level.rawValue + 1)!
                s.pendingBefore = i
                s.strikes = 0
            }
        } else {
            // Interference cleared: step down at once.
            s.strikes = 0
            if s.level > .off { s.level = ShieldLevel(rawValue: s.level.rawValue - 1)! }
        }
        return s.level
    }
}

/// Call Mode detection: debounces the end of a call so muting or turning the camera off
/// for a moment does not restore and re-apply everything.
public struct CallDetector: Codable, Equatable, Sendable {
    public var inCall = false
    public var lastSignalAt: Double?
    public var startedAt: Double?
    public init() {}

    public static let endDebounce = 1.5

    /// Returns (inCall, changed).
    public mutating func update(signal: Bool, now: Double) -> (inCall: Bool, changed: Bool) {
        if signal {
            lastSignalAt = now
            if !inCall {
                inCall = true
                startedAt = now
                return (true, true)
            }
            return (true, false)
        }
        if inCall, let last = lastSignalAt, now - last >= Self.endDebounce {
            inCall = false
            startedAt = nil
            return (false, true)
        }
        return (inCall, false)
    }
}
