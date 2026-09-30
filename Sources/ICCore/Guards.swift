/// S4 Connection Guard and Write Guard: decisions over what libproc reports for
/// an app's open sockets and files. The daemon collects the raw facts; these
/// functions decide.
public struct SocketFact: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case tcp, udp, other }
    public var kind: Kind
    public var listening: Bool
    public var established: Bool
    public var localPort: Int
    public var remotePort: Int
    public var remoteIsLoopback: Bool
    /// Bytes queued in the socket's send and receive buffers.
    public var queuedBytes: Int
    /// Stable key for "have I seen this connection before".
    public var key: String

    public init(kind: Kind, listening: Bool = false, established: Bool = false, localPort: Int = 0,
                remotePort: Int = 0, remoteIsLoopback: Bool = false, queuedBytes: Int = 0, key: String = "") {
        self.kind = kind
        self.listening = listening
        self.established = established
        self.localPort = localPort
        self.remotePort = remotePort
        self.remoteIsLoopback = remoteIsLoopback
        self.queuedBytes = queuedBytes
        self.key = key
    }
}

public struct FileFact: Codable, Equatable, Sendable {
    /// File name only (never the path).
    public var name: String
    public var openForWriting: Bool
    public var secondsSinceModified: Double

    public init(name: String, openForWriting: Bool, secondsSinceModified: Double) {
        self.name = name
        self.openForWriting = openForWriting
        self.secondsSinceModified = secondsSinceModified
    }
}

public enum Guards {
    /// Connection verdicts. `firstSeen` remembers when each connection key was first
    /// seen for this app and is updated in place (keys no longer present are dropped).
    public static func connection(_ sockets: [SocketFact], firstSeen: inout [String: Double], now: Double,
                                  settings: Config.GuardSettings) -> (active: Bool, serving: Bool) {
        var seen: [String: Double] = [:]
        var active = false
        let listeningPorts = Set(sockets.filter { $0.kind == .tcp && $0.listening }.map(\.localPort))
        var serving = false
        for s in sockets where s.kind == .tcp && s.established {
            let first = firstSeen[s.key] ?? now
            seen[s.key] = first
            if listeningPorts.contains(s.localPort) { serving = true }
            guard !s.remoteIsLoopback, !settings.benignRemotePorts.contains(s.remotePort) else { continue }
            // Without per-socket traffic counters (not exposed to unprivileged callers),
            // "recent activity" means data queued now, or a connection that is still new.
            if s.queuedBytes > 0 || now - first < settings.connectionQuietSeconds { active = true }
        }
        firstSeen = seen
        return (active, serving)
    }

    static let journalSuffixes = ["-wal", "-journal", "-shm"]

    /// Write verdicts.
    /// - A `*.lock` / `*.lck` file open for writing (git's `index.lock`, package-manager
    ///   locks) means an operation is in progress, however old the file is.
    /// - SQLite journals written within the window mean a transaction is in flight.
    ///   Browsers keep journals open all the time, so an idle journal does not count.
    /// - Any other file open for writing and modified within the window counts as a recent write.
    /// LevelDB `LOCK` files are held for a database's whole life, and `*.log` files are
    /// appended to by many idle apps; both are ignored.
    public static func writes(_ files: [FileFact], settings: Config.GuardSettings) -> (recentWrite: Bool, lockHeld: Bool) {
        var recent = false
        var lock = false
        for f in files {
            let isLock = f.name.hasSuffix(".lock") || f.name.hasSuffix(".lck")
            let isJournal = journalSuffixes.contains { f.name.hasSuffix($0) }
            let fresh = f.secondsSinceModified < settings.writeWindowSeconds
            if isLock && f.openForWriting { lock = true }
            if isJournal && fresh { lock = true }
            if !isLock && !isJournal && f.name != "LOCK" && !f.name.hasSuffix(".log") && f.openForWriting && fresh { recent = true }
        }
        return (recent, lock)
    }
}
