import Foundation
import Testing
@testable import ICCore

/// Golden traces: deterministic synthetic traces replayed through the engine. A policy
/// change that alters the outcome fails here until the golden files are regenerated
/// on purpose with `ICLEAN_UPDATE_GOLDEN=1 swift test --filter GoldenTraceTests`.
@Suite struct GoldenTraceTests {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// A small deterministic PRNG so the traces never depend on the platform.
    struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    static let catalog: [(id: String, mb: Double, pid: Int32)] = [
        ("com.google.Chrome", 2400, 500), ("com.microsoft.VSCode", 900, 600), ("com.figma.Desktop", 1500, 700),
        ("com.tinyspeck.slackmacgap", 700, 800), ("com.docker.docker", 2000, 900), ("com.apple.Terminal", 120, 1000),
        ("com.spotify.client", 400, 1100), ("com.example.notes", 300, 1200),
    ]

    /// `pressure(minute) -> (level, available%)`, `focus(minute) -> frontmost app index`.
    static func scenario(minutes: Int, seed: UInt64, pressure: (Int) -> (PressureLevel, Int),
                         focus: (Int, inout LCG) -> Int) -> [TraceRecord] {
        var rng = LCG(state: seed)
        var out: [TraceRecord] = []
        var front = 1
        let t0 = 1_900_000_000.0  // a fixed Tuesday
        for m in 0..<minutes {
            do {
                let t = t0 + Double(m * 60)
                let next = focus(m, &rng)
                if next >= 0, next != front {  // -1 means "stay"
                    front = next
                    out.append(.activate(catalog[front].id, name: catalog[front].id, at: t, weekday: 3, hour: 9 + m / 60))
                }
                let (level, avail) = pressure(m)
                let apps = catalog.enumerated().map { i, c in
                    AppSnapshot(id: c.id, name: c.id, processes: [ProcessIdentity(pid: c.pid, startTime: UInt64(c.pid))],
                                residentMB: c.mb + Double(m % 7) * 3, footprintMB: c.mb, cpuPercent: i == front ? 12 : 0.3,
                                isFrontmost: i == front, hasVisibleWindow: i == front,
                                signals: ActivitySignals(audioOutput: c.id == "com.spotify.client" && m < 90,
                                                         activeConnection: false, servingListener: false,
                                                         recentWrite: false, lockHeld: false))
                }
                let s = SystemSample(time: t, pressure: level, availablePercent: avail, physicalMB: 16384,
                                     compressedMB: Double(100 - avail) * 40, swapOuts: UInt64(max(0, 50 - avail)) * 1000)
                out.append(.tick(TickInput(sample: s, apps: apps, weekday: 3, hour: 9 + m / 60)))
            }
        }
        return out
    }

    static let scenarios: [String: () -> [TraceRecord]] = [
        // Healthy all morning: iClean must do nothing.
        "steady": {
            scenario(minutes: 120, seed: 1, pressure: { _ in (.normal, 55) },
                     focus: { m, r in m % 20 == 0 ? (r.next() < 0.5 ? 0 : 1) : (m < 1 ? 1 : -1) })
        },
        // Memory drains over an hour, stays in warning, briefly critical, then recovers.
        "pressure-episode": {
            scenario(minutes: 200, seed: 2, pressure: { m in
                switch m {
                case ..<60: return (.normal, 50)
                case ..<100: return (.normal, 50 - (m - 60) * 3 / 4)
                case ..<140: return (.warning, 18)
                case ..<150: return (.critical, 9)
                case ..<170: return (.warning, 17)
                default: return (.normal, 45)
                }
            }, focus: { m, r in m % 15 == 0 ? [0, 1, 1, 2][Int(r.next() * 4)] : -1 })
        },
        // Pressure flaps every few minutes: hysteresis must keep actions bounded.
        "flapping": {
            scenario(minutes: 90, seed: 3, pressure: { m in m >= 30 && (m / 3) % 2 == 0 ? (.warning, 20) : (.normal, 30) },
                     focus: { m, r in m % 10 == 0 ? Int(r.next() * 3) : -1 })
        },
    ]

    static func materialize(_ name: String) throws -> [TraceRecord] {
        let file = dir.appendingPathComponent("\(name).jsonl")
        if ProcessInfo.processInfo.environment["ICLEAN_UPDATE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try scenarios[name]!().map(Trace.encode).reduce(Data(), +).write(to: file)
        }
        return Trace.parse(try Data(contentsOf: file)).records
    }

    @Test(arguments: ["steady", "pressure-episode", "flapping"])
    func goldenReplay(name: String) throws {
        let recs = try Self.materialize(name)
        #expect(!recs.isEmpty)
        let result = Simulator.run(recs, config: activeConfig { $0.forecast.enabled = true }, hardware: hw16)
        let expectedFile = Self.dir.appendingPathComponent("\(name).expected.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["ICLEAN_UPDATE_GOLDEN"] == "1" {
            try enc.encode(result).write(to: expectedFile)
        }
        let expected = try JSONDecoder().decode(SimulationResult.self, from: Data(contentsOf: expectedFile))
        #expect(result == expected, "\(name) changed:\n\(result.text)")
    }

    @Test func goldenInvariants() throws {
        let steady = Simulator.run(try Self.materialize("steady"), config: activeConfig(), hardware: hw16)
        #expect(steady.freezes == 0 && steady.deprioritizations == 0)

        let episode = Simulator.run(try Self.materialize("pressure-episode"), config: activeConfig(), hardware: hw16)
        #expect(episode.freezes > 0)
        #expect(episode.freezesByApp.keys.allSatisfy { !["com.tinyspeck.slackmacgap", "com.docker.docker", "com.apple.Terminal"].contains($0) })
        #expect(episode.freezesByApp["com.spotify.client"] == nil)  // playing audio during the episode

        let flap = Simulator.run(try Self.materialize("flapping"), config: activeConfig(), hardware: hw16)
        #expect(flap.freezes <= 12, "flapping pressure caused \(flap.freezes) freezes")
    }
}
