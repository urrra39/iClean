import Foundation
import IOKit

/// Battery readings from the `AppleSmartBattery` IOKit service. Readable without root.
public struct BatteryReading: Codable, Equatable, Sendable {
    public var time: Double
    public var onAC: Bool
    public var percent: Double
    /// Remaining energy in watt-hours (remaining capacity x voltage).
    public var remainingWh: Double
    /// Instantaneous battery power in watts; positive while discharging.
    public var dischargeW: Double

    public init(time: Double, onAC: Bool, percent: Double, remainingWh: Double, dischargeW: Double) {
        self.time = time
        self.onAC = onAC
        self.percent = percent
        self.remainingWh = remainingWh
        self.dischargeW = dischargeW
    }
}

public protocol BatterySensor {
    func read(now: Double) -> BatteryReading?
}

public struct SmartBattery: BatterySensor {
    public init() {}

    public static func properties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return props?.takeRetainedValue() as? [String: Any]
    }

    public func read(now: Double) -> BatteryReading? {
        guard let p = Self.properties() else { return nil }
        func num(_ k: String) -> Double? { (p[k] as? NSNumber)?.doubleValue }
        let mV = num("Voltage") ?? num("AppleRawBatteryVoltage") ?? 0
        // Amperage is a signed 64-bit value in mA (negative while discharging).
        let mA = (p["InstantAmperage"] as? NSNumber)?.int64Value ?? (p["Amperage"] as? NSNumber)?.int64Value ?? 0
        // On Apple Silicon CurrentCapacity/MaxCapacity are percentages; the mAh values
        // live in BatteryData (RemainingCapacity) or the AppleRaw* keys on older Macs.
        let data = p["BatteryData"] as? [String: Any] ?? [:]
        let percent = num("CurrentCapacity") ?? 0
        let remaining_mAh = (data["RemainingCapacity"] as? NSNumber)?.doubleValue ?? num("AppleRawCurrentCapacity")
            ?? ((data["NominalChargeCapacity"] as? NSNumber)?.doubleValue).map { $0 * percent / 100 } ?? 0
        guard mV > 0, remaining_mAh > 0 else { return nil }
        return BatteryReading(time: now, onAC: (p["ExternalConnected"] as? Bool) ?? false, percent: percent,
                              remainingWh: remaining_mAh * mV / 1e6, dischargeW: Double(-mA) * mV / 1e6)
    }
}

/// Per-process energy from `proc_pid_rusage` (`RUSAGE_INFO_V6`, nanojoules). Zero where
/// the kernel does not report it; nil if the call fails (older macOS or no access).
public func processEnergyNJ(_ pid: Int32) -> UInt64? {
    var ri = rusage_info_v6()
    let ok = withUnsafeMutablePointer(to: &ri) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
    } == 0
    return ok ? ri.ri_energy_nj : nil
}
