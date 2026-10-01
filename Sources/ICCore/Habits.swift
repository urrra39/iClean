import Foundation

/// S3 Habit statistics: first-order counts of "which app comes to the front next",
/// per coarse time bucket, with smoothing and daily decay. Plain frequency counting.
/// Stores bundle identifiers and counts only.
public struct HabitTable: Codable, Equatable, Sendable {
    /// bucket -> from -> to -> count
    public var counts: [String: [String: [String: Double]]] = [:]
    /// Transitions added today per "bucket|from|to", to cap unusual days.
    public var today: [String: Int] = [:]
    public var day: Int = 0

    public init() {}

    /// A single day adds at most this many transitions per pair, so one odd day
    /// (a demo, a debugging marathon) cannot dominate the table.
    public static let dailyCapPerPair = 20
    public static let decayPerDay = 0.98
    public static let smoothing = 0.5
    /// Predictions need at least this many observed transitions from the current app.
    public static let minSupport = 5.0

    /// `wd` or `we` plus a 6-hour block, e.g. `wd-12`.
    public static func bucket(weekday: Int, hour: Int) -> String {
        let weekend = weekday == 1 || weekday == 7
        return "\(weekend ? "we" : "wd")-\((hour / 6) * 6)"
    }

    public mutating func record(from: String, to: String, bucket: String, day: Int) {
        guard from != to else { return }
        advance(to: day)
        let key = "\(bucket)|\(from)|\(to)"
        guard today[key, default: 0] < Self.dailyCapPerPair else { return }
        today[key, default: 0] += 1
        counts[bucket, default: [:]][from, default: [:]][to, default: 0] += 1
    }

    mutating func advance(to newDay: Int) {
        guard newDay > day else { return }
        if day > 0 {
            let factor = pow(Self.decayPerDay, Double(newDay - day))
            for (b, froms) in counts {
                for (f, tos) in froms {
                    var kept: [String: Double] = [:]
                    for (t, c) in tos where c * factor >= 0.05 { kept[t] = c * factor }
                    counts[b]![f] = kept.isEmpty ? nil : kept
                }
                if counts[b]!.isEmpty { counts[b] = nil }
            }
        }
        day = newDay
        today = [:]
    }

    /// Smoothed P(next = `to` | current = `from`) and the number of observations behind it.
    public func probability(from: String, to: String, bucket: String) -> (p: Double, support: Double) {
        let row = counts[bucket]?[from] ?? [:]
        let total = row.values.reduce(0, +)
        let k = Double(row.count + 1)
        let p = ((row[to] ?? 0) + Self.smoothing) / (total + Self.smoothing * k)
        return (p, total)
    }

    /// Most likely next apps, best first. Empty when support is too low.
    public func predict(from: String, bucket: String, top: Int = 3) -> [(id: String, p: Double)] {
        let row = counts[bucket]?[from] ?? [:]
        let total = row.values.reduce(0, +)
        guard total >= Self.minSupport else { return [] }
        return row.keys.map { ($0, probability(from: from, to: $0, bucket: bucket).p) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(top).map { (id: $0.0, p: $0.1) }
    }
}

/// Offline evaluation of habit predictions over a recorded activation sequence:
/// predict before learning each step, then learn it.
public struct HabitEvaluation: Codable, Equatable, Sendable {
    public var predictions = 0
    public var top1Hits = 0
    public var top3Hits = 0

    public var top1Rate: Double? { predictions > 0 ? Double(top1Hits) / Double(predictions) : nil }
    public var top3Rate: Double? { predictions > 0 ? Double(top3Hits) / Double(predictions) : nil }

    public static func run(activations: [(time: Double, id: String, weekday: Int, hour: Int)]) -> HabitEvaluation {
        var table = HabitTable()
        var e = HabitEvaluation()
        for (prev, cur) in zip(activations, activations.dropFirst()) where prev.id != cur.id {
            let b = HabitTable.bucket(weekday: cur.weekday, hour: cur.hour)
            let guess = table.predict(from: prev.id, bucket: b)
            if !guess.isEmpty {
                e.predictions += 1
                if guess.first?.id == cur.id { e.top1Hits += 1 }
                if guess.contains(where: { $0.id == cur.id }) { e.top3Hits += 1 }
            }
            table.record(from: prev.id, to: cur.id, bucket: b, day: Int(cur.time / 86400))
        }
        return e
    }
}
