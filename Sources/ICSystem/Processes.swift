import Darwin
import Foundation
import ICCore

/// One same-user process as libproc reports it.
public struct ProcInfo: Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var startTime: UInt64   // microseconds since 1970
    public var uid: uid_t
    public var name: String
    public var path: String
    public var stopped: Bool
    public var residentMB: Double
    public var footprintMB: Double
    public var cpuNanos: UInt64

    public var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }
}

public enum Proc {
    static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(tb.denom))
    }()

    /// BSD info for one PID, or nil if it does not exist (or is not visible).
    public static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    public static func startTime(_ pid: Int32) -> UInt64? {
        bsdInfo(pid).map { UInt64($0.pbi_start_tvsec) * 1_000_000 + UInt64($0.pbi_start_tvusec) }
    }

    public static func path(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    public static func info(_ pid: Int32) -> ProcInfo? {
        guard let b = bsdInfo(pid) else { return nil }
        var ri = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        } == 0
        let name = withUnsafeBytes(of: b.pbi_name) { raw -> String in
            let s = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            return s.isEmpty ? withUnsafeBytes(of: b.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } : s
        }
        let cpu = ok ? (ri.ri_user_time + ri.ri_system_time) * timebase.numer / timebase.denom : 0
        return ProcInfo(pid: pid, ppid: Int32(b.pbi_ppid),
                        startTime: UInt64(b.pbi_start_tvsec) * 1_000_000 + UInt64(b.pbi_start_tvusec),
                        uid: b.pbi_uid, name: name, path: path(pid), stopped: b.pbi_status == UInt32(SSTOP),
                        residentMB: ok ? Double(ri.ri_resident_size) / 1_048_576 : 0,
                        footprintMB: ok ? Double(ri.ri_phys_footprint) / 1_048_576 : 0,
                        cpuNanos: cpu)
    }

    public static func allPIDs() -> [Int32] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(max(0, got)))).filter { $0 > 0 }
    }

    /// All processes owned by the current user.
    public static func table() -> [Int32: ProcInfo] {
        let uid = getuid()
        var out: [Int32: ProcInfo] = [:]
        for pid in allPIDs() {
            if let p = info(pid), p.uid == uid { out[pid] = p }
        }
        return out
    }

    /// `pid` and every ancestor up to launchd.
    public static func ancestors(of pid: Int32) -> Set<Int32> {
        var out: Set<Int32> = []
        var p = pid
        while p > 1, !out.contains(p), let b = bsdInfo(p) {
            out.insert(p)
            p = Int32(b.pbi_ppid)
        }
        return out
    }
}

/// Sends signals only to processes whose identity still matches (safety invariant 2).
public enum Signals {
    public enum Outcome: Equatable, Sendable {
        case sent
        /// No process with this PID, or it now has a different start time (reused PID).
        case stale
        case failed(Int32)
    }

    /// Verifies PID, start time and owner, then signals.
    public static func send(_ sig: Int32, to id: ProcessIdentity) -> Outcome {
        guard let b = Proc.bsdInfo(id.pid),
              UInt64(b.pbi_start_tvsec) * 1_000_000 + UInt64(b.pbi_start_tvusec) == id.startTime else { return .stale }
        guard b.pbi_uid == getuid() else { return .failed(EPERM) }
        if kill(id.pid, sig) == 0 { return .sent }
        return errno == ESRCH ? .stale : .failed(errno)
    }

    /// Freezes a whole tree. The journal entries are written before the first signal.
    /// If any live process cannot be stopped, everything stopped so far is resumed and
    /// removed from the journal again (all-or-nothing, safety invariant 4).
    /// `send` is replaceable so tests can inject a failure part-way through a tree.
    public static func freezeTree(_ ids: [ProcessIdentity], appID: String, at now: Double, journal: JournalStore,
                                  send: (Int32, ProcessIdentity) -> Outcome = { Signals.send($0, to: $1) })
        -> (ok: Bool, stopped: [ProcessIdentity], error: String?) {
        do {
            try journal.update { $0.add(ids.map { JournalEntry(pid: $0.pid, startTime: $0.startTime, appID: appID, frozenAt: now) }) }
        } catch {
            return (false, [], "journal write failed: \(error)")
        }
        var stopped: [ProcessIdentity] = []
        var gone: [ProcessIdentity] = []
        for id in ids {
            switch send(SIGSTOP, id) {
            case .sent: stopped.append(id)
            case .stale: gone.append(id)
            case .failed(let e):
                for s in stopped.reversed() { _ = Signals.send(SIGCONT, to: s) }
                try? journal.update { $0.remove(Set(ids)) }
                return (false, [], "SIGSTOP \(id.pid) failed: \(String(cString: strerror(e)))")
            }
        }
        // The root process vanished: this is not the app we meant to freeze any more.
        if stopped.isEmpty || gone.contains(where: { $0 == ids.first }) {
            for s in stopped { _ = Signals.send(SIGCONT, to: s) }
            try? journal.update { $0.remove(Set(ids)) }
            return (false, [], "process exited")
        }
        if !gone.isEmpty { try? journal.update { $0.remove(Set(gone)) } }
        return (true, stopped, nil)
    }

    /// Resumes a tree and drops it from the journal. Resuming comes first; the journal
    /// is only cleaned up afterwards, so a crash in between errs toward "thaw again".
    @discardableResult
    public static func thawTree(_ ids: [ProcessIdentity], journal: JournalStore) -> [Outcome] {
        let out = ids.map { send(SIGCONT, to: $0) }
        try? journal.update { $0.remove(Set(ids)) }
        return out
    }

    /// Thaws everything in the journal (identity-checked) and clears it. Used on daemon
    /// start, by the watchdog, and by `iclean thaw --all` when the daemon is not running.
    public static func recover(journal: JournalStore) -> (thawed: Int, stale: Int, corrupt: Bool) {
        switch journal.load() {
        case .ok(let j):
            var thawed = 0, stale = 0
            for step in Recovery.plan(j, startTime: Proc.startTime) {
                switch step {
                case .thaw(let e):
                    if send(SIGCONT, to: e.identity) == .sent { thawed += 1 } else { stale += 1 }
                case .stale:
                    stale += 1
                }
            }
            try? FileManager.default.removeItem(at: journal.url)
            return (thawed, stale, false)
        case .corrupt:
            // Without a readable journal, resume every stopped same-user process that
            // belongs to an app bundle. Job-control stops in terminals (plain CLI
            // processes) are left alone.
            var thawed = 0
            for p in Proc.table().values where p.stopped && p.path.contains(".app/") {
                if send(SIGCONT, to: p.identity) == .sent { thawed += 1 }
            }
            return (thawed, 0, true)
        }
    }

    /// Background priority band for a tree (ladder step 1), or back to normal.
    public static func setBackground(_ ids: [ProcessIdentity], _ on: Bool) -> Int {
        var n = 0
        for id in ids where Proc.startTime(id.pid) == id.startTime {
            if setpriority(PRIO_DARWIN_PROCESS, id_t(id.pid), on ? PRIO_DARWIN_BG : 0) == 0 { n += 1 }
        }
        return n
    }
}
