import Foundation
import Testing

@testable import ICCore

@Suite struct AppClassTests {
    @Test func classesAndDefaults() {
        #expect(AppClass.of("com.tinyspeck.slackmacgap") == .comm)
        #expect(AppClass.of("com.apple.mail") == .comm)
        #expect(AppClass.of("com.spotify.client") == .media)
        #expect(AppClass.of("com.google.Chrome") == .browser)
        #expect(AppClass.of("com.example.editor") == .other)
        // Every COMM and MEDIA app is Tier S by default: observed, never paused.
        for id in AppClass.commIDs.union(AppClass.mediaIDs) { #expect(Protection.defaultTier(for: id) == .never, "\(id)") }
        #expect(Protection.defaultTier(for: "com.google.Chrome") == .auto)
    }

    /// MEDIA: never paused while playing, nor for the cooldown after it stopped.
    @Test func audioCooldown() {
        let player = app("com.example.player")
        let ctx = { (t: Double) in PolicyContext(now: t, config: Config(), lastActiveAt: [player.id: -10_000], lastAudioAt: [player.id: 0])
        }
        #expect(Policy.skipReasons(player, ctx(60)).map(\.code).contains(Code.audioRecent))
        #expect(!Policy.skipReasons(player, ctx(601)).map(\.code).contains(Code.audioRecent))
        let e = engine(apps: [player])
        var playing = player
        playing.signals.audioOutput = true
        _ = e.tick(TickInput(sample: sample(0, .critical), apps: [playing]))
        let r = e.tick(TickInput(sample: sample(120, .critical), apps: [player]))
        #expect(r.actions.of(.freeze).isEmpty)
        #expect(e.tick(TickInput(sample: sample(700, .critical), apps: [player])).actions.of(.freeze).ids == [player.id])
    }

    /// BROWSER: a longer idle threshold, and wake windows long enough to reconnect.
    @Test func browserCaution() {
        let ctx = PolicyContext(now: 0, config: Config())
        #expect(ctx.idleThreshold("com.google.Chrome") == 30)
        #expect(ctx.idleThreshold("com.example.editor") == 15)
        var c = Config()
        c.wakeWindows = ["com.google.Chrome": WakeWindow(thawSeconds: 10, everyMinutes: 5)]
        #expect(c.validate().contains { $0.path == "wakeWindows.com.google.Chrome" && $0.severity == .error })
        c.wakeWindows = ["com.google.Chrome": WakeWindow(thawSeconds: 30, everyMinutes: 5)]
        #expect(!c.validate().contains { $0.path == "wakeWindows.com.google.Chrome" })
    }

    /// COMM with a wake window: resumed on schedule, never refrozen during a call.
    @Test func wakeWindowNeverRefreezesDuringACall() {
        let slack = app("com.tinyspeck.slackmacgap", mb: 800)
        let c = activeConfig { $0.wakeWindows = [slack.id: WakeWindow(thawSeconds: 30, everyMinutes: 10)] }
        let e = engine(c, apps: [slack])
        #expect(e.tick(TickInput(sample: sample(0, .critical), apps: [slack])).actions.of(.freeze).count == 1)
        #expect(e.tick(TickInput(sample: sample(600, .critical), apps: [slack])).actions.of(.thaw).count == 1)
        var call = SessionContext()
        call.microphoneInUse = true
        let during = e.tick(TickInput(sample: sample(631, .critical), apps: [slack], session: call))
        #expect(during.actions.of(.freeze).isEmpty && !during.focusSafe.isEmpty)
    }

    @Test func compatReport() {
        let s = Compat.report(id: "com.spotify.client", name: "Spotify", config: Config())
        #expect(s.contains("MEDIA") && s.contains("Tier: S") && s.contains("media keys"))
        var c = Config()
        c.tiers["com.tinyspeck.slackmacgap"] = .auto
        c.wakeWindows["com.tinyspeck.slackmacgap"] = WakeWindow(thawSeconds: 20, everyMinutes: 5)
        let slack = Compat.report(id: "com.tinyspeck.slackmacgap", name: "Slack", config: c)
        #expect(slack.contains("COMM") && slack.contains("set in your config") && slack.contains("thawed 20 s every 5 min"))
        #expect(Compat.report(id: "com.apple.Terminal", name: "Terminal", config: Config()).contains("Protected"))
        #expect(Compat.report(id: "com.google.Chrome", name: "Chrome", config: Config()).contains("whole process tree"))
    }
}
