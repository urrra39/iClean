/// Runaway guard: sustained CPU spin and steady memory growth, detected from a
/// sliding window of per-app samples. It only ever suggests actions.
public struct RunawayState: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var t: Double
        public var cpu: Double
        public var residentMB: Double
    }
    public var series: [String: [Point]] = [:]
    public var lastNotified: [String: Double] = [:]
    public init() {}
}

public struct RunawayFinding: Codable, Equatable, Sendable {
    public var appID: String
    public var name: String
    public var code: String
    public var detail: String
}

public enum Runaway {
    /// Adds this tick's samples and returns the apps that are running away now.
    /// `notify` holds only the findings that are due a (rate-limited) notification.
    public static func update(_ s: inout RunawayState, apps: [AppSnapshot], now: Double,
                              settings: Config.RunawaySettings) -> (current: [RunawayFinding], notify: [RunawayFinding]) {
        let keep = max(settings.cpuMinutes, settings.growthWindowMinutes) * 60
        var present = Set<String>()
        var current: [RunawayFinding] = []
        for app in apps where !Protection.isProtected(app) {
            present.insert(app.id)
            var pts = s.series[app.id, default: []]
            pts.append(.init(t: now, cpu: app.cpuPercent, residentMB: app.residentMB))
            pts.removeAll { now - $0.t > keep }
            s.series[app.id] = pts

            let cpuWindow = pts.filter { now - $0.t <= settings.cpuMinutes * 60 }
            if let first = cpuWindow.first, now - first.t >= settings.cpuMinutes * 60 * 0.9,
               cpuWindow.count >= 3, cpuWindow.allSatisfy({ $0.cpu >= settings.cpuPercent }), !app.isFrontmost {
                let avg = cpuWindow.map(\.cpu).reduce(0, +) / Double(cpuWindow.count)
                current.append(.init(appID: app.id, name: app.name, code: Code.runawayCPU,
                                     detail: "\(Int(avg))% CPU for \(Int(settings.cpuMinutes)) min in the background"))
            }
            if let first = pts.first, now - first.t >= settings.growthWindowMinutes * 60 * 0.9, pts.count >= 5,
               let fit = linearFit(pts.map { ($0.t / 60, $0.residentMB) }),
               fit.slope >= settings.growthMBPerMinute, fit.r2 >= 0.8 {
                current.append(.init(appID: app.id, name: app.name, code: Code.runawayMemory,
                                     detail: "memory growing \(Int(fit.slope)) MB/min steadily"))
            }
        }
        for id in s.series.keys where !present.contains(id) { s.series[id] = nil }

        var notify: [RunawayFinding] = []
        for f in current where now - (s.lastNotified[f.appID] ?? -.infinity) >= settings.notifyEveryHours * 3600 {
            s.lastNotified[f.appID] = now
            notify.append(f)
        }
        return (current, notify)
    }

    /// Least-squares line through (x, y); nil with fewer than two distinct x values.
    public static func linearFit(_ pts: [(Double, Double)]) -> (slope: Double, r2: Double)? {
        let n = Double(pts.count)
        guard n >= 2 else { return nil }
        let mx = pts.map(\.0).reduce(0, +) / n
        let my = pts.map(\.1).reduce(0, +) / n
        let sxx = pts.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
        let syy = pts.map { ($0.1 - my) * ($0.1 - my) }.reduce(0, +)
        let sxy = pts.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
        return (slope, r2)
    }
}
