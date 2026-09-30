import ApplicationServices
import CoreAudio
import CoreGraphics
import CoreMediaIO
import Foundation
import ICCore
import IOKit.pwr_mgt

/// Which processes are playing or recording audio (CoreAudio process objects,
/// macOS 14.2+). On older systems attribution is unavailable and iClean relies on
/// power assertions, which media players hold while playing.
public enum AudioActivity {
    public static var available: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    public static func pids() -> (output: Set<Int32>, input: Set<Int32>) {
        guard #available(macOS 14.2, *) else { return ([], []) }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else {
            return ([], [])
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return ([], [])
        }
        var out = Set<Int32>(), inp = Set<Int32>()
        for id in ids {
            let pid: Int32 = read(id, kAudioProcessPropertyPID) ?? 0
            let o: UInt32 = read(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            let i: UInt32 = read(id, kAudioProcessPropertyIsRunningInput) ?? 0
            if pid > 0, o != 0 { out.insert(pid) }
            if pid > 0, i != 0 { inp.insert(pid) }
        }
        return (out, inp)
    }

    static func read<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, p) == noErr else { return nil }
        return p.pointee
    }

    /// Is the default input device (microphone) running for anyone?
    public static func microphoneInUse() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else {
            return false
        }
        let running: UInt32 = read(dev, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0
        return running != 0
    }
}

public enum Camera {
    /// True if any camera is running for any process (CoreMediaIO). Cannot say which.
    public static func inUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == 0 else { return false }
        for d in devices {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }
}

public enum PowerAssertions {
    /// Assertion types that mean "this process is doing something the user cares about".
    static let relevant: Set<String> = ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep",
                                        "PreventSystemSleep", "NoIdleSleepAssertion", "NoDisplaySleepAssertion"]

    public static func pids() -> Set<Int32> {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let d = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var out = Set<Int32>()
        for (pid, list) in d where list.contains(where: { relevant.contains($0["AssertType"] as? String ?? "") }) {
            out.insert(pid.int32Value)
        }
        return out
    }
}

public struct WindowFacts: Sendable {
    /// Owners of at least one on-screen, not fully covered, normal-layer window.
    public var visiblePIDs: Set<Int32>
    /// Owner of a window that exactly covers a display (fullscreen).
    public var fullscreenPIDs: Set<Int32>
}

public enum Windows {
    /// Works without Screen Recording: only owner PID, layer, alpha and bounds are used.
    public static func facts() -> WindowFacts {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let displays = activeDisplays().map { CGDisplayBounds($0) }
        var above: [CGRect] = []   // front-to-back order
        var visible = Set<Int32>(), full = Set<Int32>()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01, rect.width * rect.height >= 1600 else { continue }
            // Conservative occlusion: only a single opaque window above that fully
            // contains this one counts as covering it.
            if !above.contains(where: { $0.contains(rect) }) { visible.insert(pid) }
            if displays.contains(where: { $0 == rect }) { full.insert(pid) }
            if alpha >= 0.99 { above.append(rect) }
        }
        return WindowFacts(visiblePIDs: visible, fullscreenPIDs: full)
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        return ids
    }

    public static func mirrored() -> Bool {
        activeDisplays().contains { CGDisplayIsInMirrorSet($0) != 0 }
    }
}

public enum SessionProbe {
    /// Processes that only run while the screen is being shared.
    static let sharingProcessNames: Set<String> = ["screensharingd", "CptHost", "ScreenSharingSubscriber"]

    public static func context(frontmostPID: Int32?, windows: WindowFacts) -> SessionContext {
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return SessionContext(cameraInUse: Camera.inUse(), microphoneInUse: AudioActivity.microphoneInUse(),
                              screenSharing: !allProcessNames().isDisjoint(with: sharingProcessNames),
                              displayMirrored: Windows.mirrored(),
                              frontmostFullscreen: frontmostPID.map { windows.fullscreenPIDs.contains($0) } ?? false,
                              screenLocked: locked)
    }

    /// Names of all processes, including other users' (screensharingd runs as root),
    /// in one `sysctl(KERN_PROC_ALL)` call.
    static func allProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return Set(procs.prefix(size / MemoryLayout<kinfo_proc>.stride).map { p in
            withUnsafeBytes(of: p.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        })
    }
}

public enum Permissions {
    public struct Status: Codable, Sendable {
        public var accessibility: Bool
        public var screenRecording: Bool
        public var inputMonitoring: Bool
    }

    /// Preflight only; never shows a prompt.
    public static func status() -> Status {
        Status(accessibility: AXIsProcessTrusted(), screenRecording: CGPreflightScreenCaptureAccess(),
               inputMonitoring: CGPreflightListenEventAccess())
    }
}
