/// The freeze journal: every process iClear stops is written here *before* the
/// signal is sent, so a crash can never leave anything frozen. This file holds the
/// pure parts: the record format and the recovery plan.
public struct JournalEntry: Codable, Hashable, Sendable {
    public var pid: Int32
    public var startTime: UInt64
    public var appID: String
    public var frozenAt: Double

    public init(pid: Int32, startTime: UInt64, appID: String, frozenAt: Double) {
        self.pid = pid
        self.startTime = startTime
        self.appID = appID
        self.frozenAt = frozenAt
    }

    public var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }
}

public struct Journal: Codable, Equatable, Sendable {
    public var version = 1
    public var entries: [JournalEntry] = []

    public init(entries: [JournalEntry] = []) { self.entries = entries }

    public mutating func add(_ e: [JournalEntry]) {
        let existing = Set(entries.map(\.identity))
        entries += e.filter { !existing.contains($0.identity) }
    }

    public mutating func remove(appID: String) { entries.removeAll { $0.appID == appID } }
    public mutating func remove(_ ids: Set<ProcessIdentity>) { entries.removeAll { ids.contains($0.identity) } }

    public var appIDs: Set<String> { Set(entries.map(\.appID)) }
}

public enum RecoveryStep: Equatable, Sendable {
    /// Same PID, same start time: this is the process iClear froze. Send SIGCONT.
    case thaw(JournalEntry)
    /// The PID is gone or now belongs to a different process: do not signal it.
    case stale(JournalEntry)
}

public enum Recovery {
    /// Plans recovery for a journal. `startTime(pid)` returns the current start time of
    /// a PID, or nil if no such process exists. Only exact identity matches are thawed,
    /// so a reused PID is never signalled.
    public static func plan(_ journal: Journal, startTime: (Int32) -> UInt64?) -> [RecoveryStep] {
        journal.entries.map { e in
            startTime(e.pid) == e.startTime ? .thaw(e) : .stale(e)
        }
    }
}
