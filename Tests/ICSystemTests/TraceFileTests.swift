import Foundation
import Testing

@testable import ICCore
@testable import ICSystem

/// Trace files: a day's file rotates to `.1` at the size cap; limits delete the oldest
/// files and keep the one being written; reading returns records oldest first.
@Suite struct TraceFileTests {
    func file(_ dir: URL, _ name: String, bytes: Int, age: Double) throws {
        let u = dir.appendingPathComponent(name)
        try Data(repeating: 0x0A, count: bytes).write(to: u)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
    }

    @Test func limitsDeleteOldestAndKeepTheCurrentFile() throws {
        let dir = tempHome().home.appendingPathComponent("traces")
        var settings = Config.TraceSettings()
        settings.maxMB = 20.0 / 1024  // 20 KB
        let w = TraceWriter(dir: dir, settings: settings)
        try file(dir, "2026-10-01.jsonl", bytes: 1024, age: 86400)
        try file(dir, "2026-10-02.jsonl.1", bytes: 15 * 1024, age: 7200)
        try file(dir, "2026-10-02.jsonl", bytes: 10 * 1024, age: 0)
        w.enforceLimits(now: Date().timeIntervalSince1970)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left == ["2026-10-02.jsonl"])
    }

    @Test func readIsOldestFirst() throws {
        let dir = tempHome().home.appendingPathComponent("traces")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func rec(_ t: Double) -> Data { Trace.encode(.activate("a", name: "A", at: t, weekday: 2, hour: 9)) }
        try (rec(1) + rec(2)).write(to: dir.appendingPathComponent("2026-10-02.jsonl.1"))
        try rec(3).write(to: dir.appendingPathComponent("2026-10-02.jsonl"))
        try rec(0).write(to: dir.appendingPathComponent("2026-10-01.jsonl"))
        #expect(TraceWriter.read(dir: dir, since: 0).records.map(\.t) == [0, 1, 2, 3])
    }
}
