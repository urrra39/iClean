# Signature features: status and evidence

A signature feature is on by default only if its measured benefit on the reference
machine was positive and its false-positive budget held. Otherwise it ships off, with
the result written down here. "Synthetic" means the golden traces in
`Tests/ICCoreTests/Fixtures`, which are generated, not recorded from real use.

| # | Feature | Default | Why |
|---|---|---|---|
| S1 | Pressure Forecast | ETA shown; **actions off** | No real pressure events on this machine yet to measure lead time or false alarms |
| S2 | Regret-aware decisions | **on** | Can only remove or delay freezes, never add them; regret rate is always reported |
| S3 | Habit statistics | **on** for P(return soon); **pre-thaw off** | Pre-thaw measured no benefit (35.0 vs 35.9 ms) |
| S4 | Connection and Write Guard | **on** | Safety feature; measured cost 1.0 ms p50 for every regular app |
| S5 | Post-thaw health check and quarantine | **on** | Safety feature; crash-after-thaw quarantine covered by an integration test |
| S6 | Traces and `iclean simulate` | **on** (local, 7 days, 20 MB cap) | Needed for S1-S3 evaluation; nothing leaves the Mac |
| S7 | Workspaces and staged thaw | workspaces **on**; staged thaw **off** (opt-in `stagedThaw`) | One run, mixed result: first app usable 16.7 ms vs 37.7 ms, but all four 71.9 ms vs 40.1 ms |
| S8 | RAM right-sizing advisor | command available; refuses under 7 days of data | Not evaluated: less than 7 days of history exist |

## S1 Pressure Forecast

**Method.** EWMA (alpha 0.3) of the per-sample slope of `kern.memorystatus_level`, an
EWMA of squared deviations for spread, and linear extrapolation to the level at which
this Mac was last seen entering warning (median of recorded transitions; 25% until one
is seen). Range = slope ± one standard deviation. No training.
([`Forecast.swift`](../Sources/ICCore/Forecast.swift))

**Self-disarm.** Each alarm is scored: a hit if warning arrives while it is open, a
false alarm if it stays normal for twice the horizon. After 5 alarms, if more than
30% were false, forecast-driven actions switch themselves off and the digest says so
(test: `falseAlarmStormDisarms`).

**Results.** Synthetic only: the gradual "pressure-episode" trace gave 1 hit with 17
minutes of lead and no false alarms. The "flapping" trace, where pressure jumps with
no trend, gave 10 misses. That is expected: a trend estimate cannot predict a step.
Real lead time and false-alarm rate on this machine: **not yet measured**. The
benchmark's pressure run compressed the victim without reaching the warning level,
so no transition was recorded.

## S2 Regret-aware decisions

Every freeze, real or (in Observe mode) virtual, becomes a record: estimated and
realized relief, how it ended, thaw latency when measurable, and a regret flag (the
user came back within 5 minutes, or the thaw took longer than 500 ms). A candidate is
frozen only if

```
net = (relief / target) × pressureWeight × (1 − P(return soon)) − P(return soon) × min(1, expectedThawMs / budgetMs)
```

is at least `regret.minNetValue` (0). Per-app regret (EWMA 0.3) above 0.5 doubles the
app's idle threshold (up to 8 h); above 0.8 demotes it to Tier S. More than 5
regretted freezes in 24 h makes iClean act only on critical pressure for the next 24 h.

**Results.** Synthetic: 0 regretted of 3 closed freezes (pressure-episode); the
flapping trace ends with its 3 freezes still open. Real regret rate: **not yet measured**. It shows up in `iclean stats`
after Observe mode has run.

## S3 Habit statistics

First-order counts of "which app comes to the front next", per weekday/weekend and
6-hour block. Laplace smoothing (0.5), 2% decay per day, at most 20 transitions per
pair per day (so one unusual day cannot dominate), and at least 5 observations before
any prediction. `iclean habits show | reset | export`. Bundle IDs and counts only.

**Pre-thaw gate (measured).** Cold thaw: 35.94 ms from user arrival to working set
back; pre-thawed 2 s early: 34.96 ms. Resuming early does not fault pages back in, so
there is no measurable benefit. Pre-thaw ships off; habits only feed P(return soon).
Offline top-1/top-3 hit rate on real use: **not yet measured** (the evaluator,
`HabitEvaluation`, is tested on a synthetic alternating sequence).

## S4 Connection Guard and Write Guard

libproc (`PROC_PIDLISTFDS`, `PROC_PIDFDSOCKETINFO`, `PROC_PIDFDVNODEPATHINFO`) works
without root for same-user processes. An app is never frozen until both guards were
inspected (`SKIP_GUARDS_NOT_INSPECTED`). Inspection runs only when iClean may act,
for at most 12 apps per tick and 4096 descriptors per process.

- `SKIP_CONN_ACTIVE`: an established TCP connection to a non-loopback peer that has
  queued bytes, or is younger than 120 s. Per-socket traffic counters are not
  available without privileges, so "recent activity" means exactly this. Ports
  5223/5228 (push services) are allowed by default.
- `SKIP_LISTENER`: a listening socket with an accepted connection (a dev server with a
  client).
- `SKIP_WRITE_RECENT`: a file open for writing and modified within 60 s (`*.log` and
  LevelDB `LOCK` ignored).
- `SKIP_LOCKFILE`: a `*.lock` / `*.lck` file open for writing, or a SQLite
  `-wal`/`-journal`/`-shm` file modified within 60 s.

**Limits.** UDP and QUIC have no connection state, so they are not judged. Advisory
locks (`flock`) are not visible through libproc; only lock files by name are.

**Results.** Integration tests with `ic-hog` holding a listener with a client, a
file being written, and an `index.lock` (`GuardInspectionTests`). Cost: 1.02 ms p50,
3.23 ms max to inspect every regular app. How often guards block otherwise-eligible
freezes in real use: counted in `iclean stats` ("Guard saves"), **not yet measured**.

## S5 Post-thaw health check and quarantine

Two seconds after every thaw the root process must still exist with the same start
time. With Accessibility, iClean also asks the app for its `AXRole` with a 2 s
timeout. Unresponsive means hung. If the app disappears within 5 minutes and a new
crash report for it exists, that also counts. Unhealthy apps are quarantined (Tier S
with the reason), notified once, and listed by `iclean quarantine`.

**Results.** `crashAfterThawIsQuarantined` (an `ic-hog` that aborts on SIGCONT) passes.
Hang detection needs Accessibility and is covered only by unit tests of the decision
logic.

## S6 Traces and simulation

Format: [TRACE_FORMAT.md](TRACE_FORMAT.md). `iclean simulate --config other.json
--since 7d` replays recorded inputs through the same engine. Output is labelled
SIMULATION: it cannot model how iClean's actions would have changed later memory
readings. `iclean trace export --anonymize` replaces bundle IDs with salted hashes and
drops PIDs. Golden traces run in CI (`GoldenTraceTests`). Corrupt, oversized and
future-version lines are skipped (`corruptInputIsSkipped`).

## S7 Workspaces and staged thaw

`workspaces` in the config names groups of apps. `iclean workspace <name> freeze`
freezes all running members or none (any member failing a safety check refuses the
whole group). When several apps thaw at once (wake, unlock, "thaw all", workspace),
they go in order of most recent use. With `"stagedThaw": true` each one is also
delayed by the previous app's reclaimed memory divided by the measured fault-in
speed, capped at 10 s in total. By default they all resume at once.

**Results.** One pressure run, 4 × 128 MB, comparing one-after-another with all at once:

| | first app usable | all four usable |
|---|---|---|
| one after another | 16.7 ms | 71.9 ms |
| all at once | 37.7 ms | 40.1 ms |

The first app gained 21 ms and the whole set lost 32 ms. That is one run with no
spread, the benchmark staged by waiting for each app rather than with the engine's
timed delays, and the app being activated is always resumed first anyway. That does
not show a net benefit, so staged thaw ships **off**. Focus-mode binding is not
implemented (no verified public mechanism was tested). Workspaces use manual and
profile triggers only.

## S8 RAM right-sizing advisor

`iclean advise` needs at least 7 days with 60 or more per-minute samples each. It
reports the 90th-99th percentile of used memory plus 25% headroom, rounded up to RAM
sizes Macs ship with, and always labels the result an estimate. It refuses to guess
with less data, and it has no purchase links. **Not evaluated:** the holdout check
(`Advisor.holdout`) needs 14 days of history, and none exists yet.
