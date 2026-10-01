import Foundation
import ICCore

/// Where iClear keeps its files. Everything lives in one directory so uninstall is
/// one `rm -r`. `ICLEAR_HOME` replaces the home directory (tests, lab and soak
/// instances); `ICLEAR_INSTANCE` names a separate instance (its own LaunchAgent label).
public struct Paths: Sendable {
    /// The home directory iClear works under (the real one unless `ICLEAR_HOME` is set).
    public let home: URL
    /// Instance name for non-default installs ("isolated" when only `ICLEAR_HOME` is set).
    public let instance: String?
    public let base: URL
    public let launchAgents: URL
    /// Where iClean (the project's former name) kept its data.
    public let legacyBase: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let custom = environment["ICLEAR_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        home = custom ?? FileManager.default.homeDirectoryForCurrentUser
        let name = environment["ICLEAR_INSTANCE"].flatMap { $0.isEmpty ? nil : $0 }
        instance = name ?? (custom == nil ? nil : "isolated")
        let lib = home.appendingPathComponent("Library")
        base = lib.appendingPathComponent("Application Support/iClear" + (name.map { "-" + $0 } ?? ""))
        launchAgents = lib.appendingPathComponent("LaunchAgents")
        legacyBase = lib.appendingPathComponent("Application Support/iClean")
    }

    public var config: URL { base.appendingPathComponent("config.json") }
    public var state: URL { base.appendingPathComponent("state.json") }
    public var journal: URL { base.appendingPathComponent("journal.json") }
    public var actions: URL { base.appendingPathComponent("actions.jsonl") }
    public var traces: URL { base.appendingPathComponent("traces") }
    public var socket: URL { base.appendingPathComponent("icleard.sock") }
    public var lock: URL { base.appendingPathComponent("icleard.lock") }
    public var hardware: URL { base.appendingPathComponent("hardware.json") }
    /// Lab mode only: identities of the processes the lab harness registered.
    public var labRegistry: URL { base.appendingPathComponent("lab-registry.json") }

    public func ensure() throws {
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
}

public enum Files {
    /// Writes via a temporary file, fsync and rename, so readers see the old or the
    /// new content and never a torn file, even if the process dies mid-write.
    public static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let ok = data.withUnsafeBytes { buf -> Bool in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n <= 0 { return false }
                off += n
            }
            return fsync(fd) == 0
        }
        let err = errno
        close(fd)
        guard ok, rename(tmp.path, url.path) == 0 else {
            unlink(tmp.path)
            throw POSIXError(POSIXErrorCode(rawValue: ok ? errno : err) ?? .EIO)
        }
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL, pretty: Bool = false) throws {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        try atomicWrite(try e.encode(value), to: url)
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    /// Appends one line; rotates to `<name>.1` when the file passes `maxBytes`.
    public static func appendLine(_ data: Data, to url: URL, maxBytes: Int) {
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = URL(fileURLWithPath: url.path + ".1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return }
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
}

/// The freeze journal on disk. Written before every SIGSTOP.
public final class JournalStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public enum LoadResult: Equatable {
        case ok(Journal)
        /// The file was unreadable; it was moved aside and a fallback scan is needed.
        case corrupt(movedTo: URL)
    }

    public func load() -> LoadResult {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return .ok(Journal()) }
        if let j = try? JSONDecoder().decode(Journal.self, from: data) { return .ok(j) }
        let aside = URL(fileURLWithPath: url.path + ".corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: url, to: aside)
        return .corrupt(movedTo: aside)
    }

    public func read() -> Journal {
        if case .ok(let j) = load() { return j }
        return Journal()
    }

    /// Read-modify-write under the lock.
    public func update(_ body: (inout Journal) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var j = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Journal.self, from: $0) } ?? Journal()
        body(&j)
        if j.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try Files.writeJSON(j, to: url)
        }
    }
}

/// Timestamped JSON Lines log of every action, for `iclear stats`, `explain` and the menu.
public struct ActionLogEntry: Codable, Sendable {
    public var t: Double
    public var action: Action
    public var outcome: String

    public init(t: Double, action: Action, outcome: String) {
        self.t = t
        self.action = action
        self.outcome = outcome
    }
}

public enum ActionLog {
    public static func append(_ e: ActionLogEntry, paths: Paths) {
        guard let d = try? JSONEncoder().encode(e) else { return }
        Files.appendLine(d + Data([0x0A]), to: paths.actions, maxBytes: 5 << 20)
    }

    public static func read(paths: Paths, last: Int = 200) -> [ActionLogEntry] {
        let files = [URL(fileURLWithPath: paths.actions.path + ".1"), paths.actions]
        let dec = JSONDecoder()
        let all = files.compactMap { try? Data(contentsOf: $0) }.flatMap {
            $0.split(separator: 0x0A).compactMap { try? dec.decode(ActionLogEntry.self, from: Data($0)) }
        }
        return Array(all.suffix(last))
    }
}

/// Daily trace files with a total size cap and retention.
public final class TraceWriter: @unchecked Sendable {
    let dir: URL
    var settings: Config.TraceSettings
    private var bytesSinceCheck = 0

    public init(dir: URL, settings: Config.TraceSettings) {
        self.dir = dir
        self.settings = settings
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func update(settings: Config.TraceSettings) { self.settings = settings }

    public func write(_ r: TraceRecord) {
        guard settings.enabled else { return }
        let day = Self.dayFormatter.string(from: Date(timeIntervalSince1970: r.t))
        let data = Trace.encode(r)
        Files.appendLine(data, to: dir.appendingPathComponent("\(day).jsonl"), maxBytes: Int(settings.maxMB * 1_048_576))
        bytesSinceCheck += data.count
        if bytesSinceCheck > 256 << 10 {
            bytesSinceCheck = 0
            enforceLimits(now: r.t)
        }
    }

    /// Deletes traces older than the retention and the oldest ones past the size cap.
    public func enforceLimits(now: Double) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.contains(".jsonl") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var total = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        for f in files {
            let mtime =
                (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? now
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if now - mtime > Double(settings.retentionDays) * 86400 || Double(total) > settings.maxMB * 1_048_576 {
                try? fm.removeItem(at: f)
                total -= size
            }
        }
    }

    public static func read(dir: URL, since: Double) -> (records: [TraceRecord], skipped: Int) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.contains(".jsonl") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var recs: [TraceRecord] = []
        var skipped = 0
        for f in files {
            guard let d = try? Data(contentsOf: f) else { continue }
            let (r, s) = Trace.parse(d)
            recs += r.filter { $0.t >= since }
            skipped += s
        }
        return (recs, skipped)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
