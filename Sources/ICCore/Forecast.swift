import Foundation

/// S1 Pressure Forecast: deterministic trend estimation, no training.
///
/// Tracks `kern.memorystatus_level` (percent available). The slope is an EWMA of
/// per-sample slopes; its spread is an EWMA of squared deviations. The ETA to
/// yellow is a linear extrapolation to the level at which this machine was seen
/// entering warning pressure (learned from real transitions).
public struct ForecastState: Codable, Equatable, Sendable {
    public var lastTime: Double?
    public var lastAvailable: Double?
    public var slope: Double?          // percent per minute
    public var slopeVariance = 0.0
    public var lastLevel: PressureLevel = .normal
    /// `availablePercent` values seen at normal -> warning and warning -> critical transitions.
    public var warningLevels: [Double] = []
    public var criticalLevels: [Double] = []
    public var openAlarmAt: Double?
    /// Last outcomes, newest last: true = hit, false = false alarm.
    public var outcomes: [Bool] = []
    public var leadTimesMinutes: [Double] = []
    public var missed = 0
    public var hitsTotal = 0
    public var falseAlarmsTotal = 0
    public var armed = true

    public init() {}

    static let defaultWarningLevel = 25.0
    static let alpha = 0.3
    static let maxHistory = 20

    public var warningLevel: Double { median(warningLevels) ?? Self.defaultWarningLevel }
    public var criticalLevel: Double { median(criticalLevels) ?? warningLevel / 2 }
    public var alarms: Int { outcomes.count }
    public var falseAlarms: Int { outcomes.filter { !$0 }.count }
}

public struct Forecast: Codable, Equatable, Sendable {
    /// Minutes to yellow (warning); `nil` when stable or already there.
    public var etaWarning: Double?
    public var etaWarningLow: Double?
    public var etaWarningHigh: Double?
    public var etaCritical: Double?
    public var slopePerMinute: Double?
    public var armed: Bool
    public var stable: Bool

    public init(armed: Bool, stable: Bool) {
        self.armed = armed
        self.stable = stable
    }

    public var summary: String {
        guard let eta = etaWarning else { return stable ? "stable" : "no trend yet" }
        let low = etaWarningLow.map { String(format: "%.0f", $0) } ?? "?"
        let high = etaWarningHigh.map { String(format: "%.0f", $0) } ?? "∞"
        let red = etaCritical.map { String(format: ", red in ~%.0f min", $0) } ?? ""
        return String(format: "yellow in ~%.0f min (range %@-%@ min)%@", eta, low, high, red)
    }
}

public enum Forecaster {
    /// Feeds one sample. Returns the forecast and whether a new alarm was raised.
    public static func update(_ s: inout ForecastState, sample: SystemSample, settings: Config.ForecastSettings)
        -> (Forecast, alarmRaised: Bool) {
        let t = sample.time
        let avail = Double(sample.availablePercent)
        let level = sample.pressure

        // Learn thresholds and score open alarms on real transitions.
        if level > s.lastLevel {
            if s.lastLevel == .normal {
                s.warningLevels = Array((s.warningLevels + [avail]).suffix(ForecastState.maxHistory))
                if let a = s.openAlarmAt {
                    s.outcomes = Array((s.outcomes + [true]).suffix(ForecastState.maxHistory))
                    s.leadTimesMinutes = Array((s.leadTimesMinutes + [(t - a) / 60]).suffix(200))
                    s.hitsTotal += 1
                    s.openAlarmAt = nil
                } else {
                    s.missed += 1
                }
            }
            if level == .critical {
                s.criticalLevels = Array((s.criticalLevels + [avail]).suffix(ForecastState.maxHistory))
            }
        }
        if let a = s.openAlarmAt, level == .normal, t - a > settings.horizonMinutes * 2 * 60 {
            s.outcomes = Array((s.outcomes + [false]).suffix(ForecastState.maxHistory))
            s.falseAlarmsTotal += 1
            s.openAlarmAt = nil
        }
        s.lastLevel = level

        // Trend.
        if let lt = s.lastTime, let la = s.lastAvailable, t > lt {
            let inst = (avail - la) / ((t - lt) / 60)
            if let old = s.slope {
                let new = old + ForecastState.alpha * (inst - old)
                s.slopeVariance += ForecastState.alpha * ((inst - new) * (inst - new) - s.slopeVariance)
                s.slope = new
            } else {
                s.slope = inst
            }
        }
        s.lastTime = t
        s.lastAvailable = avail

        // Self-disarm when the false-alarm rate on this machine exceeds the budget.
        if s.alarms >= settings.minAlarmsToJudge {
            s.armed = Double(s.falseAlarms) / Double(s.alarms) <= settings.falseAlarmBudget
        }

        var f = Forecast(armed: s.armed && settings.enabled, stable: true)
        f.slopePerMinute = s.slope
        guard level == .normal, let slope = s.slope else { return (f, false) }
        let sd = s.slopeVariance.squareRoot()
        let gap = avail - s.warningLevel
        if gap <= 0 {
            f.etaWarning = 0; f.etaWarningLow = 0; f.etaWarningHigh = 0; f.stable = false
        } else if slope < -0.05 {
            f.stable = false
            f.etaWarning = gap / -slope
            f.etaWarningLow = gap / -(slope - sd)
            f.etaWarningHigh = slope + sd < 0 ? gap / -(slope + sd) : nil
            f.etaCritical = (avail - s.criticalLevel) / -slope
        }
        var raised = false
        if let eta = f.etaWarning, eta <= settings.horizonMinutes, s.openAlarmAt == nil {
            s.openAlarmAt = t
            raised = true
        }
        return (f, raised)
    }
}

func median(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func percentile(_ xs: [Double], _ p: Double) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}
