import Foundation

/// F5 Anti-Beachball forensics: what was going on when the frontmost app stopped
/// answering. Only observations; the explanation names what iClear cannot fix.
public struct Offender: Codable, Equatable, Sendable {
    public var name: String
    public var cpuPercent: Double
    public var diskMBps: Double

    public init(name: String, cpuPercent: Double, diskMBps: Double) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.diskMBps = diskMBps
    }
}

public struct StallEvent: Codable, Equatable, Sendable {
    public var at: Double
    public var appID: String
    public var name: String
    /// How long the app took to answer (or the probe timeout).
    public var durationMs: Double
    public var pageinsPerSec: Double
    public var swapinsPerSec: Double
    public var busyCores: Double
    public var cores: Int
    public var pressure: PressureLevel
    public var thermal: Thermal
    public var offenders: [Offender]
    public var causes: [String] = []

    public init(
        at: Double, appID: String, name: String, durationMs: Double, pageinsPerSec: Double, swapinsPerSec: Double,
        busyCores: Double, cores: Int, pressure: PressureLevel, thermal: Thermal, offenders: [Offender]
    ) {
        self.at = at
        self.appID = appID
        self.name = name
        self.durationMs = durationMs
        self.pageinsPerSec = pageinsPerSec
        self.swapinsPerSec = swapinsPerSec
        self.busyCores = busyCores
        self.cores = cores
        self.pressure = pressure
        self.thermal = thermal
        self.offenders = offenders
    }
}

public enum Forensics {
    /// Ranked, plain-language causes for a stall.
    public static func explain(_ e: StallEvent) -> [String] {
        var c: [String] = []
        if e.swapinsPerSec > 50 || e.pressure >= .warning {
            c.append(
                String(
                    format: "memory: the Mac was paging (%.0f swap-ins/s, pressure %@); pausing idle apps frees memory for the next time",
                    e.swapinsPerSec, e.pressure.name))
        } else if e.pageinsPerSec > 2000 {
            c.append(String(format: "disk reads: %.0f page-ins/s (files being read or mapped)", e.pageinsPerSec))
        }
        if let top = e.offenders.max(by: { $0.diskMBps < $1.diskMBps }), top.diskMBps > 50 {
            c.append(String(format: "disk: %@ was moving %.0f MB/s", top.name, top.diskMBps))
        }
        if e.busyCores >= Double(e.cores) * 0.9, let top = e.offenders.max(by: { $0.cpuPercent < $1.cpuPercent }) {
            c.append(String(format: "CPU: all %d cores busy; largest user process %@ at %.0f%%", e.cores, top.name, top.cpuPercent))
        }
        if e.thermal >= .serious { c.append("heat: the Mac was slowing itself down to cool off") }
        if c.isEmpty {
            c.append(
                "no outside cause measured: most likely the app itself, or system work iClear cannot see or change (indexing, kernel, other users' processes, hardware)"
            )
        }
        return c
    }

    public static func stats(_ events: [StallEvent]) -> String {
        guard !events.isEmpty else { return "No stalls recorded." }
        let d = events.map(\.durationMs).sorted()
        func p(_ q: Double) -> Double { d[min(d.count - 1, Int(Double(d.count - 1) * q))] }
        var byApp: [String: Int] = [:]
        for e in events { byApp[e.name, default: 0] += 1 }
        let apps = byApp.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        var byCause: [String: Int] = [:]
        for e in events { byCause[String(e.causes.first?.prefix(while: { $0 != ":" }) ?? "unknown"), default: 0] += 1 }
        let causes = byCause.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        return String(
            format: "%d stalls; duration p50 %.0f ms, p95 %.0f ms, max %.0f ms. By app: %@. First cause: %@.",
            events.count, p(0.5), p(0.95), d.last!, apps, causes)
    }
}

/// F6 pre-launch advisor: will launching this app push memory pressure up?
public struct LaunchAdvice: Codable, Equatable, Sendable {
    public var appName: String
    public var enoughData: Bool
    public var typicalMB: Double?
    public var highMB: Double?
    public var availableMB: Double
    public var verdict: String
    public var suggestions: [String]
    public var text: String
}

public enum LaunchAdvisor {
    public static let minSamples = 30

    /// - Parameters:
    ///   - usage: this Mac's own history for the app (from the engine state).
    ///   - warningLevel: available-memory percent at which this Mac entered warning.
    ///   - pausable: idle apps that could be paused, with their resident memory.
    public static func advise(
        name: String, usage: AppUsage?, sample: SystemSample, warningLevel: Double,
        pausable: [(name: String, mb: Double)]
    ) -> LaunchAdvice {
        let available = sample.physicalMB * Double(sample.availablePercent) / 100
        guard let u = usage, u.samples >= minSamples else {
            return LaunchAdvice(
                appName: name, enoughData: false, availableMB: available, verdict: "not enough data", suggestions: [],
                text:
                    "Not enough history for \(name) (\(usage?.samples ?? 0) of \(minSamples) samples while it ran). iClear will not guess.")
        }
        let typical = u.averageMB
        let high = max(u.maxMB ?? typical, typical)
        let floor = sample.physicalMB * warningLevel / 100
        let verdict: String
        var need = 0.0
        if available - high >= floor {
            verdict = "fits"
        } else if available - typical >= floor {
            verdict = "tight: it may push memory into yellow at its peak"
            need = floor - (available - high)
        } else {
            verdict = "likely pushes memory into yellow (warning)"
            need = floor - (available - high)
        }
        var suggestions: [String] = []
        var freed = 0.0
        for p in pausable.sorted(by: { $0.mb > $1.mb }) where freed < need {
            suggestions.append(p.name)
            freed += p.mb * Policy.reliefFactor
        }
        var text = String(
            format: "ESTIMATE for %@ from %d samples on this Mac: typically %.0f MB, up to %.0f MB. Available now: %.0f MB. Verdict: %@.",
            name, u.samples, typical, high, available, verdict)
        if !suggestions.isEmpty {
            text +=
                " Pausing " + suggestions.joined(separator: ", ")
                + String(format: " would leave roughly %.0f MB more as the system needs it.", freed)
        } else if need > 0 {
            text += " No idle app is large enough to make room."
        }
        return LaunchAdvice(
            appName: name, enoughData: true, typicalMB: typical, highMB: high, availableMB: available, verdict: verdict,
            suggestions: suggestions, text: text)
    }
}
