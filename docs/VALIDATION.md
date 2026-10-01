# Validation results

Results for the criteria in [RELEASE_CRITERIA.md](RELEASE_CRITERIA.md), measured on
2026-10-01. Distributions are given as p50 / p95 / p99 / max with N. "0 failures in N
trials" bounds the failure rate, it does not show it is zero (rule of three: below
3/N with 95% confidence).

## How the lab was run

- **Machine.** Apple M3 Pro (Mac15,6), 18 GB, macOS 27.0.1, the maintainer's daily-use
  Mac with its own apps open. Results describe this one Mac.
- **Harness.** `ic-lab validate <phase>` (source in `Sources/ic-lab/`), built in release
  mode and run from `.work/lab/` through a small launcher app ("iClear Lab", made by
  `scripts/lab-app.sh`) so that the Accessibility permission covers the harness.
- **Fixtures.** Real apps started by the lab with throwaway data, each as its own new
  instance: Google Chrome with a temporary `--user-data-dir` and a local HTML page;
  Visual Studio Code with temporary `--user-data-dir` and `--extensions-dir`,
  extensions disabled, a scratch folder; TextEdit with a scratch text file; Preview
  with a generated PDF. A copy of an app that was already running is never used.
  Documents are opened, never edited, and checksummed (SHA-256) after every cycle.
- **Scope lock.** Every signal checks a registry of the process identities (PID and
  start time) the lab started; the lab daemons run with `ICLEAR_LAB=1` and see only
  those. The user's own copy of Chrome was running during the lab and was never
  signalled. Activation targets the exact fixture process through Accessibility.
- **Induced pressure.** 256 MB allocations of random (incompressible) data, at most
  45% of RAM (the lab's limit is 50%), released at once on critical pressure or when
  swap grows by more than 1 GB. The level reached is reported with each result.
- **Responsiveness.** "Thaw-to-responsive" is the time from SIGCONT until the app's
  main thread answers an Accessibility request; no answer within 5 s is a hang.
- **Crash reports.** New `.ips`/`.crash`/`.hang` files in
  `~/Library/Logs/DiagnosticReports` whose name matches a fixture and whose PID was a
  fixture process.
- **Power and heat.** The owner asked for the non-battery phases to run on AC power.
  The Mac was on AC from 14:24 until it was unplugged in the afternoon; the phases from
  the side-effect lab on ran **on battery** (80% down), as the owner later asked not
  to wait. Each result lists the power source and thermal state sampled during the run
  (once per cycle, pair or minute); all samples so far were thermal "nominal".

## Battery (C9): no valid trial set yet

Battery estimates and `iclear battery target` stay **experimental and off** until
valid unplugged trials exist. Trials run only when the Mac is unplugged; the harness
refuses to start on AC and aborts a trial, recording it as "invalidated: AC
connected", if the power source changes during it. Invalid trials are never averaged.

| Run | Trial | Status | Spinners measured | Predicted saving | Measured saving |
|---|---|---|---|---|---|
| A | 1 | discarded: method flaw (no settling time; the battery reading lags 47-60 s) | 6.79 W | 6.79 W | 3.88 W |
| B | 1 | discarded: a compile ran during the measurement window | | | |
| C | 1 | valid (uncalibrated: scale 1) | 6.96 W | 6.96 W | 5.72 W (error 22%) |
| C | 2 | invalidated: AC connected | | | |

One valid short trial is not evidence. C9 needs three unplugged trials of at least
30 minutes; they have not been run.

## Side effects (stage 3, E1-E4)

Run 2026-10-01 18:42-19:20 on battery (80% → 70%), thermal nominal throughout.
Simulators: `ic-media-sim` (a quiet tone with Now Playing), `ic-call-sim` (microphone
input), `ic-chat-sim` (a chat server and two clients: "naive" relies on the socket to
report a dropped connection; "heartbeat" also reconnects after 15 s without hearing from
the server). Chrome ran with a throwaway profile, hidden, with nine local pages (form,
timers, WebSocket chat, WebRTC data channel loopback, service worker, paused media,
audio, microphone call, download). The chat server sends a message every 10 s, pings
every 5 s and drops a client it has not heard from for 30 s, as chat servers do.

### Guards (E2): 123 of 123 freeze attempts blocked

Attempts go through the lab daemon's direct-request path (`iclear freeze`), which skips
the idle and tier checks but never a guard.

| Situation | Attempts | Blocked by a guard | Frozen | The specific guard named |
|---|---|---|---|---|
| Player playing audio | 20 | 20 | 0 | `SKIP_AUDIO_ACTIVE` 20/20 |
| Call app using the microphone | 20 | 20 | 0 | `SKIP_MIC_ACTIVE` 20/20 |
| Chrome tab playing audio | 20 | 20 | 0 | `SKIP_AUDIO_ACTIVE` 9/20 (all 20 also blocked by `SKIP_POWER_ASSERTION`) |
| Chrome tab in a call (microphone) | 20 | 20 | 0 | `SKIP_MIC_ACTIVE` 18/20, `SKIP_AUDIO_RECENT` 14/20 (all 20 also `SKIP_POWER_ASSERTION`) |
| Chrome download (200 MB over 90 s) | 40 | 40 | 0 | `SKIP_POWER_ASSERTION` 40/40, `SKIP_WRITE_RECENT` 40/40 |
| Player within the 1-minute audio cooldown | 3 | 3 | 0 | `SKIP_AUDIO_ACTIVE` 1, `SKIP_AUDIO_RECENT` 1 (see below) |

Findings, each fixed with a test:

- Chrome's per-process audio and microphone readings came and went between readings
  (9/20 and 18/20 above), while the lab's own readings saw them on. Other guards blocked
  every attempt here, but a call app with nothing else going on could have been paused
  in a gap. Fix: the union of three readings 50 ms apart, and the cooldown now also
  covers the microphone and starts at the first reading without audio
  (`microphoneAndFlickerKeepTheCooldown`, commit b659bfa).
- A direct freeze request used the app's state from the last tick, up to 30 s old
  (`freezeRequestUsesCurrentSignals`, commit db990df).
- With two copies of an app running (the lab's Chrome and the owner's), launchd-parented
  helpers such as Chrome's crash handler were claimed by both copies, which hid the lab's
  copy from the scope-locked daemon (`launchdHelpersJoinOnlyASingleCopy`, commit c50fdb3).
- The cooldown row: the media simulator had been quarantined in an earlier, interrupted
  run (it was killed right after a resume, which the health check treats as a crash),
  so the "allowed after the cooldown" step could not be shown. The lab now starts each
  run with a fresh daemon home; the player part is re-run below.

### What a pause does (E1, E3)

The guards refused every freeze of the test Chrome (power assertion, connections, recent
writes, lock files), so the lab paused it directly to measure the effect of a pause.

| Subject | Pause | N | Server dropped it | Reconnected after resume | Messages late / worst delay | First page report after resume | Broken 45-60 s later |
|---|---|---|---|---|---|---|---|
| Chrome (all tabs) | 10 s | 5 | 0/5 | not needed | 0-1 / 2-9 s | ≤ 0.03 s | 0/5 |
| Chrome (all tabs) | 60 s | 3 | 3/3 | 1.04-1.10 s | 6 / 54-60 s | ≤ 0.03 s | 0/3 |
| Chrome (all tabs) | 300 s | 2 | 2/2 | 1.06-1.11 s | 29-30 / 291-297 s | ≤ 0.03 s | 0/2 |
| Chat client with heartbeat | 10 s | 3 | 0/3 | not needed | 1 / 4 s | | 0/3 |
| Chat client with heartbeat | 60 s | 3 | 3/3 | 1.05-1.11 s | 6 / 55 s | | 0/3 |
| Chat client with heartbeat | 300 s | 2 | 2/2 | 1.05-1.10 s | 30 / 296 s | | 0/2 |
| Chat client with heartbeat, wake window 20 s every 60 s | 300 s | 2 | 2/2 | in the first wake window | 20 / 36 s | | 0/2 |
| Naive chat client | 10 s | 3 | 0/3 | not needed | 1 / 4 s | | 0/3 |
| Naive chat client | 60 s | 3 | 1/3 | **never** | - | | **3/3** |
| Naive chat client | 300 s (plain and wake window) | 4 | 0/4 | **never** | - | | **4/4** |

- **Data (E1): no loss.** The 200 MB download completed and matched the server's
  checksum; Chrome's form values were unchanged after every pause; the heartbeat client
  and Chrome received 213/213 messages each (late, never lost). The naive client
  received 26 of 213: messages were not lost on the server, but the client never came
  back to fetch them.
- **Connections (E3).** Chrome's pages and the heartbeat client always recovered. The
  naive client stayed disconnected after every pause of 60 s or more: `URLSessionWebSocketTask`
  did not report the server's close after the resume, and the client had no heartbeat
  of its own. An app built that way stays offline until something else wakes it. As
  pre-registered, the class this affects (chat, mail, calendar: COMM) is **protected by
  default**, and wake windows are opt-in with the tradeoff documented.
- **Timers and clocks.** Wall-clock and monotonic time both include the pause. After a
  pause, a repeating timer fires once (Chrome's 1 s interval after a 300 s pause: one
  callback, no burst of 300), so code that counts ticks sees a gap, and timeouts measured
  across the pause expire right after resume.
- **WebRTC and service worker.** The data-channel loopback and the service worker kept
  working after every pause, up to 300 s. The step that scheduled a notification to
  fall inside a 60 s pause sent back no report at all, shown or failed, so what happens
  to a notification due during a pause was **not measured**; the README lists it as
  "late or missing".
- **Crashes.** 0 new crash reports; 0 crash dumps in the throwaway Chrome profile.
- Not tested: TLS session behavior beyond the TCP connection it rides on (the chat
  server uses plain WebSocket on the loopback interface); real Slack, Spotify or any
  account (manual steps in [MANUAL_TESTS_APPS.md](MANUAL_TESTS_APPS.md)); media keys
  sent to a paused player (needs synthetic key events, which need Accessibility; manual).

## Crash recovery (C2)

`kill -9` of a scope-locked lab daemon while all four real-app fixtures (Chrome, VS Code,
TextEdit, Preview) were frozen: **100/100** trials had every fixture running again,
recovery p50 76.3 ms, p95 80.4 ms, p99 83.3 ms, max 88.4 ms (N=100; on battery,
thermal nominal). The 50 trials with an active stash did not arm in the first run (the
lab refreshed its registry only when each daemon started, and Chrome's new helpers left
it out of scope); they are re-run with a registry refresh every second.

## Reclaim on real apps (§8.4 item 3)

Four real-app fixtures frozen, then up to 45% of RAM (8.1 GB) of incompressible memory
allocated by the lab and held 5 s; resident memory of each frozen app (whole tree) read
before, during, and 10 s after thaw. 10 episodes, on battery, thermal nominal. Peak
pressure reached "warning" in episodes 1 and 3; the rest stayed "normal" at the cap.

| Fixture | Episode 1 (warning): before → frozen | Change | All 10 episodes: median change |
|---|---|---|---|
| Google Chrome (9 processes) | 1203 → 803 MB | −33% | −1% |
| Visual Studio Code (9 processes) | 1709 → 1046 MB | −39% | −4% |
| TextEdit | 74 → 58 MB | −22% | −4% |
| Preview | 130 → 84 MB | −35% | −4% |

The episodes are not independent: after a thaw, compressed or swapped pages stay out of
RAM until the app touches them (10 s after thaw the apps were still at their reduced
size), so later episodes found the apps already small. What frozen apps give back
depends on real pressure: at "normal" pressure macOS reclaims little from them.
