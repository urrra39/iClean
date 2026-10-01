/// Context profiles and hardware (RAM) profiles. Each is a small, documented delta
/// applied to the user's config; see docs/ARCHITECTURE.md.
public enum ProfileName: String, Codable, CaseIterable, Sendable {
    case work, batterySaver, presentation, dev
}

public enum RAMProfile: String, Codable, Sendable {
    /// <= 8 GB: act earliest, shorter idle thresholds.
    case small
    /// 9-24 GB: the defaults.
    case balanced
    /// >= 32 GB: mostly observe; act only on critical pressure.
    case large

    public init(memoryGB: Double) {
        self = memoryGB <= 8 ? .small : memoryGB >= 32 ? .large : .balanced
    }
}

/// Picks the active context profile. Manual choice wins, then presentation
/// signals, then the schedule, then battery.
public func activeProfile(
    settings: Config.ProfileSettings, session: SessionContext, sample: SystemSample,
    weekday: Int, hour: Int
) -> ProfileName {
    if let m = settings.manual { return m }
    if settings.autoPresentation, session.displayMirrored || session.screenSharing { return .presentation }
    if let rule = settings.schedule.first(where: { $0.weekdays.contains(weekday) && hour >= $0.startHour && hour < $0.endHour }) {
        return rule.profile
    }
    if settings.autoBatterySaver, sample.onBattery { return .batterySaver }
    return .work
}

/// Focus Safe Mode: automatic action pauses during meetings, screen sharing,
/// presentations and fullscreen use.
public func focusSafeReasons(session: SessionContext, profile: ProfileName) -> [String] {
    var out: [String] = []
    if profile == .presentation { out.append("presentation profile") }
    if session.cameraInUse { out.append("camera in use") }
    if session.microphoneInUse { out.append("microphone in use") }
    if session.screenSharing { out.append("screen sharing") }
    if session.displayMirrored { out.append("display mirrored") }
    if session.frontmostFullscreen { out.append("fullscreen app in front") }
    return out
}

/// Config after hardware and context deltas. Only thresholds move; safety rules never do.
public func effectiveConfig(_ base: Config, hardware: Hardware, profile: ProfileName) -> Config {
    var c = base
    switch RAMProfile(memoryGB: hardware.memoryGB) {
    case .small:
        c.idleMinutes *= 0.66
    case .balanced:
        break
    case .large:
        c.idleMinutes *= 1.5
    }
    if hardware.rotationalDisk {
        // Swap-in from a spinning disk is slow: freeze less, and only for more relief.
        c.maxFrozenApps = min(c.maxFrozenApps, 3)
        c.reliefTargetWarningMB *= 0.5
    }
    switch profile {
    case .work, .presentation:
        break
    case .batterySaver:
        c.idleMinutes *= 0.66
        c.runaway.cpuMinutes = min(c.runaway.cpuMinutes, 2)
    case .dev:
        c.idleMinutes *= 1.5
    }
    return c
}

/// Whether the RAM profile allows acting at this pressure level at all.
public func profileAllowsAction(_ hardware: Hardware, level: PressureLevel) -> Bool {
    switch RAMProfile(memoryGB: hardware.memoryGB) {
    case .small, .balanced: return level >= .warning
    case .large: return level >= .critical
    }
}

/// Apps treated as Tier S while the Dev profile is active.
public func devProtected(_ app: AppSnapshot) -> Bool {
    let devIDs: Set<String> = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.sublimetext.4",
        "dev.zed.Zed", "com.panic.Nova", "com.apple.iphonesimulator",
    ]
    return devIDs.contains(app.id) || app.id.hasPrefix("com.jetbrains.")
}
