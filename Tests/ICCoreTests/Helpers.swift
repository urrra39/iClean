@testable import ICCore

/// Builds an app that passes every eligibility check unless told otherwise.
func app(_ id: String, mb: Double = 1000, cpu: Double = 0, front: Bool = false, visible: Bool = false,
         pids: [Int32] = [], signals: ActivitySignals = ActivitySignals(activeConnection: false, servingListener: false,
                                                                       recentWrite: false, lockHeld: false),
         regular: Bool = true, origin: AppOrigin = .thirdParty, lineage: Bool = false, partial: Bool = false) -> AppSnapshot {
    let procs = (pids.isEmpty ? [Int32(abs(id.hashValue % 30000) + 1000)] : pids).map { ProcessIdentity(pid: $0, startTime: UInt64($0) * 7) }
    return AppSnapshot(id: id, name: id.components(separatedBy: ".").last ?? id, processes: procs, residentMB: mb,
                       footprintMB: mb, cpuPercent: cpu, isFrontmost: front, hasVisibleWindow: visible,
                       isRegularApp: regular, origin: origin, partialTree: partial, isDaemonLineage: lineage, signals: signals)
}

func sample(_ t: Double, _ level: PressureLevel = .normal, available: Int = 60, physicalMB: Double = 16384,
            swapOuts: UInt64 = 0, onBattery: Bool = false, battery: Int? = nil, thermal: Thermal = .nominal,
            disk: Double = 100) -> SystemSample {
    SystemSample(time: t, pressure: level, availablePercent: available, physicalMB: physicalMB, swapOuts: swapOuts,
                 thermal: thermal, onBattery: onBattery, batteryPercent: battery, freeDiskGB: disk)
}

func activeConfig(_ edit: (inout Config) -> Void = { _ in }) -> Config {
    var c = Config()
    c.mode = .active
    c.forecast.enabled = false
    edit(&c)
    return c
}

let hw16 = Hardware(memoryGB: 16)

/// An engine whose apps have all been idle long enough.
func engine(_ config: Config = activeConfig(), hardware: Hardware = hw16, apps: [AppSnapshot], at t0: Double = 0,
            idleSince: Double = -10_000) -> Engine {
    var st = EngineState(startedAt: t0)
    for a in apps { st.lastActiveAt[a.id] = idleSince }
    return Engine(config: config, hardware: hardware, state: st)
}

extension Array where Element == Action {
    func of(_ k: ActionKind) -> [Action] { filter { $0.kind == k } }
    var ids: [String] { map(\.appID) }
}
