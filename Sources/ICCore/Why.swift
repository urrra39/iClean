import Foundation

/// "Why is my Mac slow right now?": a ranked, plain-language diagnosis built only
/// from measured data.
public struct Cause: Codable, Equatable, Sendable {
    public var code: String
    /// 0-100; causes are listed highest first.
    public var severity: Int
    public var title: String
    public var detail: String
    public var suggestion: String
}

public struct Diagnosis: Codable, Equatable, Sendable {
    public var healthy: Bool
    public var causes: [Cause]
    public var health: HealthScore
    public var forecast: String

    public var text: String {
        var lines: [String] = ["Mac Health: \(health.score)/100 (\(health.band.rawValue)). Forecast: \(forecast)."]
        if healthy {
            lines.append("Your Mac is healthy; iClear is idle.")
        }
        for (i, c) in causes.enumerated() {
            lines.append("\(i + 1). \(c.title)")
            lines.append("   \(c.detail)")
            lines.append("   Suggestion: \(c.suggestion)")
        }
        return lines.joined(separator: "\n")
    }
}

public enum Why {
    /// - Parameters:
    ///   - samples: recent system samples, oldest first (a few minutes is enough).
    ///   - apps: current app snapshots.
    public static func diagnose(
        samples: [SystemSample], apps: [AppSnapshot], runaway: [RunawayFinding],
        forecast: Forecast, idleMinutes: (String) -> Double
    ) -> Diagnosis {
        guard let now = samples.last else {
            return Diagnosis(
                healthy: true, causes: [], health: Health.score(SystemSample(time: 0), swapOutMBPerMinute: 0, runawayApps: 0),
                forecast: forecast.summary)
        }
        let first = samples.first!
        let swapRate = Health.swapOutRate(first, now)
        let byMemory = apps.filter { !$0.isDaemonLineage }.sorted { $0.residentMB > $1.residentMB }
        let idleHeavy = byMemory.filter {
            !$0.isFrontmost && !$0.hasVisibleWindow && idleMinutes($0.id) >= 15 && !Protection.isProtected($0)
        }
        func names(_ xs: ArraySlice<AppSnapshot>) -> String {
            xs.map { "\($0.name) (\(mb($0.residentMB)))" }.joined(separator: ", ")
        }
        var causes: [Cause] = []

        if now.pressure >= .warning {
            let crit = now.pressure == .critical
            let target =
                idleHeavy.isEmpty
                ? "No idle heavy apps found; close something you are not using."
                : "Idle heavy apps that could be frozen or quit: \(names(idleHeavy.prefix(3)))."
            causes.append(
                Cause(
                    code: crit ? Code.pressureCritical : Code.pressureWarning, severity: crit ? 95 : 70,
                    title: "Memory pressure is \(now.pressure.name)",
                    detail:
                        "\(now.availablePercent)% of memory available; \(mb(now.compressedMB)) compressed, \(mb(now.swapUsedMB)) in swap.",
                    suggestion: target))
        }
        if swapRate > 20 {
            causes.append(
                Cause(
                    code: "SWAPPING", severity: swapRate > 200 ? 80 : 60,
                    title: "The Mac is swapping to disk",
                    detail: String(format: "%.0f MB/min written to swap over the last %.0f min.", swapRate, (now.time - first.time) / 60),
                    suggestion: "Swapping makes everything wait on the disk. Free memory by quitting or freezing idle apps."))
        }
        if now.compressedMB / max(now.physicalMB, 1) > 0.3, now.pressure == .normal {
            causes.append(
                Cause(
                    code: "COMPRESSOR_LARGE", severity: 30,
                    title: "Much memory is compressed",
                    detail:
                        "\(mb(now.compressedMB)) of \(mb(now.physicalMB)) is compressed. macOS is coping, but switching to those apps costs time.",
                    suggestion: "Nothing to do unless pressure rises."))
        }
        for r in runaway where r.code == Code.runawayCPU {
            causes.append(
                Cause(
                    code: r.code, severity: 70, title: "\(r.name) is using the CPU in the background",
                    detail: r.detail, suggestion: "Throttle it to background priority, freeze it, or quit it."))
        }
        for r in runaway where r.code == Code.runawayMemory {
            causes.append(
                Cause(
                    code: r.code, severity: 55, title: "\(r.name) keeps growing in memory",
                    detail: r.detail, suggestion: "This often means a leak; restarting the app usually fixes it."))
        }
        switch now.thermal {
        case .nominal: break
        case .fair:
            causes.append(
                Cause(
                    code: "THERMAL_FAIR", severity: 20, title: "The Mac is warm",
                    detail: "Thermal state is fair; performance is not limited yet.", suggestion: "Nothing to do."))
        case .serious, .critical:
            causes.append(
                Cause(
                    code: "THERMAL_THROTTLING", severity: now.thermal == .critical ? 90 : 70,
                    title: "The Mac is slowing itself down to cool off",
                    detail: "Thermal state is \(now.thermal == .critical ? "critical" : "serious").",
                    suggestion: "Close CPU-heavy work, keep the vents clear, avoid soft surfaces."))
        }
        if now.freeDiskGB < 10 {
            causes.append(
                Cause(
                    code: "LOW_DISK", severity: now.freeDiskGB < 5 ? 80 : 50, title: "Free disk space is low",
                    detail: String(format: "%.1f GB free. Swap needs free disk space.", now.freeDiskGB),
                    suggestion: "Free some space (see `iclear disk`). iClear never deletes files for you."))
        }
        if now.lowPowerMode {
            causes.append(
                Cause(
                    code: "LOW_POWER_MODE", severity: 30, title: "Low Power Mode is on",
                    detail: "macOS limits CPU speed to save battery.", suggestion: "Turn it off if you need full speed."))
        }
        let serious = causes.contains { $0.severity >= 50 }
        if serious, !byMemory.isEmpty {
            causes.append(
                Cause(
                    code: "TOP_MEMORY", severity: 25, title: "Largest apps by memory",
                    detail: names(byMemory.prefix(5)),
                    suggestion: "Background apps you are not using are the cheapest to free."))
        }
        causes.sort { $0.severity > $1.severity }
        let health = Health.score(now, swapOutMBPerMinute: swapRate, runawayApps: runaway.count)
        return Diagnosis(healthy: !serious && now.pressure == .normal, causes: causes, health: health, forecast: forecast.summary)
    }
}

func mb(_ x: Double) -> String {
    x >= 1024 ? String(format: "%.1f GB", x / 1024) : String(format: "%.0f MB", x)
}
