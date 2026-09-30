# Architecture

```
            ┌──────────── iCleanMenu (SwiftUI menu bar) ──┐   ┌── iclean (CLI) ──┐
            │ status, why, digest, thaw all, hotkey        │   │ all commands      │
            └───────────────────┬──────────────────────────┘   └────────┬─────────┘
                                │   Unix domain socket, 1 JSON line each way
                                ▼
┌──────────────────────── icleand (per-user LaunchAgent) ──────────────────────────┐
│ ICSystem: sample (sysctl, host_statistics64) ─┐                                  │
│           apps (NSWorkspace + libproc trees,  ├─► TickInput ─► ICCore.Engine ─► actions
│           windows, audio, power assertions)   ┘     (pure, deterministic)        │
│           guards (libproc fds, only when it may act)                             │
│ executes: journal → SIGSTOP tree │ SIGCONT → journal │ PRIO_DARWIN_BG │ terminate │
│ writes:   actions.jsonl, traces/*.jsonl, state.json                              │
└───────────────┬──────────────────────────────────────────────────────────────────┘
                │ kqueue NOTE_EXIT
        icleand --watchdog  (own session): replays the journal if the daemon dies
```

| Target | Role | System calls |
|---|---|---|
| `ICCore` | Models, config, policy, scoring, engine state machine, journal recovery plan, health score, forecast, regret, habits, guards, runaway, diagnosis, digest, advisor, traces, simulator | none |
| `ICSystem` | Sampler, process table, app collector, inspector, signals, journal store, IPC, daemon runtime, doctor, installer, bench | yes |
| `icleand` | Daemon entry point; also the watchdog (`--watchdog <pid>`) | |
| `iclean` | CLI | |
| `iCleanMenu` | Menu-bar app (macOS 13+ `MenuBarExtra`) | |
| `ic-hog` | Test process: memory, CPU, sockets, files, locks, heartbeats, crash/hang after SIGCONT | |

Floor: macOS 13 for everything (see [DECISIONS.md](DECISIONS.md) #19). Older MacBooks
are limited to the macOS versions they can run; a MacBook that cannot run macOS 13
cannot run iClean.

## Engine tick

1. Activity: the frontmost app and apps with visible windows are "active now". An app
   seen for the first time counts as active, so a new app is never idle.
2. Forecast (S1) and calibration (pressure baseline while normal).
3. Runaway guard: sustained CPU and steady memory growth (notify only).
4. Mandatory thaws: wake, unlock, low battery, shutdown, app gone, app visible or
   frontmost again, maximum frozen time, pressure normal long enough, wake windows.
   New processes in a frozen tree join the freeze.
5. Priority restore for deprioritized apps that became active or once pressure is calm.
6. Focus Safe Mode check; if paused, stop here.
7. Trigger: warning or critical pressure (RAM profile permitting), or an armed forecast
   inside its horizon. Conservative mode (regret budget exceeded) acts only on critical.
8. Eligibility (all checks, reasons recorded for `explain`), guard inspection
   required, scoring, budgets, net value (S2), then deprioritize first (warning) or
   freeze (critical), until the relief target is reached. Rounds are ≥ 60 s apart.
9. Critical pressure only: graceful quit request for frozen apps listed in `quitAllowed`.

Scoring (pure function, `Policy.score`):
`resident MB × min(max(idle / threshold, 1), 4) × (1 − risk) / (1 + activations per hour)`,
with risk 0.2 (Tier A), 0.5 (Tier B, opted in), 0.6 (Tier S, opted in) plus half the
app's regret, capped at 0.95. Relief estimate: 60% of resident memory until realized
relief is measured.

## Mac Health score

`100 − penalties`, clamped to 0-100 (`Health.score`):

| Condition | Penalty |
|---|---|
| memory pressure warning / critical | 25 / 50 |
| swap-out rate (MB/min over the last 15 min) | rate ÷ 10, max 15 |
| compressed memory above 25% of RAM | (share − 0.25) × 40, max 10 |
| thermal fair / serious / critical | 5 / 15 / 30 |
| free disk below 10 GB / 5 GB | 10 / 20 |
| runaway apps | 10 each, max 20 |

Bands: good ≥ 80, fair 50-79, poor < 50. The menu icon shows the band (and a
snowflake while anything is frozen).

## Profiles

| Profile | Delta |
|---|---|
| Work | none |
| Battery Saver (auto on battery) | idle threshold × 0.66; runaway CPU window 2 min |
| Presentation (auto on mirroring or screen sharing) | pauses all automatic action (Focus Safe Mode) |
| Dev | idle threshold × 1.5; IDEs, editors and Simulator treated as Tier S |

RAM profiles: ≤ 8 GB idle × 0.66; 9-31 GB defaults; ≥ 32 GB idle × 1.5 and act only on
critical pressure. A rotational boot disk caps frozen apps at 3 and halves the
warning relief target. Profiles only move thresholds; safety rules never change.
Schedule rules (`profiles.schedule`) and a manual override are in the config.

Focus Safe Mode pauses automatic action while the camera or microphone is in use,
the screen is shared or mirrored, the front app is fullscreen, or the Presentation
profile is active. Screen sharing is detected by process name (`screensharingd`,
`CptHost`); other sharing tools are not detected.

## Reason codes

Actions: `PRESSURE_WARNING`, `PRESSURE_CRITICAL`, `FORECAST_ETA`, `IDLE_<n>M`,
`TOP_SCORE`, `USER_REQUEST`, `WORKSPACE`, `WAKE_WINDOW`, `TREE_GREW`.
Skips: `SKIP_PROTECTED`, `SKIP_TIER_S`, `SKIP_TIER_B_NOT_OPTED_IN`, `SKIP_DENY_RULE`,
`SKIP_NOT_REGULAR_APP`, `SKIP_PARTIAL_TREE`, `SKIP_FRONTMOST`, `SKIP_VISIBLE_WINDOW`,
`SKIP_NOT_IDLE`, `SKIP_CPU_ACTIVE`, `SKIP_POWER_ASSERTION`, `SKIP_AUDIO_ACTIVE`,
`SKIP_MIC_ACTIVE`, `SKIP_CHILD_BUSY`, `SKIP_CONN_ACTIVE`, `SKIP_LISTENER`,
`SKIP_WRITE_RECENT`, `SKIP_LOCKFILE`, `SKIP_GUARDS_NOT_INSPECTED`, `SKIP_QUARANTINED`,
`SKIP_COOLDOWN`, `SKIP_PRESSURE_NORMAL`, `SKIP_LOW_NET_VALUE`, `SKIP_FROZEN_BUDGET`,
`SKIP_ALREADY_FROZEN`, `SKIP_TARGET_REACHED`, `SKIP_REGRET_BUDGET`.
Thaws: `THAW_ACTIVATED`, `THAW_MAX_DURATION`, `THAW_PRESSURE_RELIEVED`, `THAW_USER`,
`THAW_WAKE`, `THAW_UNLOCK`, `THAW_LOW_BATTERY`, `THAW_SHUTDOWN`, `THAW_PROCESS_GONE`,
`THAW_PREDICTED_RETURN`, `THAW_RECOVERY`.
Other: `RUNAWAY_CPU`, `RUNAWAY_MEMORY_GROWTH`, `UNHEALTHY_AFTER_THAW`.

## Files

Everything lives in `~/Library/Application Support/iClean/` (mode 0700), or in
`$ICLEAN_HOME` if set: `config.json`, `state.json` (engine state, learned thresholds,
habits, regret records, daily totals), `journal.json` (only while something is
frozen), `actions.jsonl` (+ `.1`, 5 MB rotation), `traces/` (daily JSON Lines, 7 days,
20 MB), `hardware.json`, `icleand.sock`, `icleand.lock`, `icleand.log`. The
LaunchAgent is `~/Library/LaunchAgents/io.github.urrra39.iclean.plist`.

## Configuration

`iclean config show` prints every key with its default. Unknown keys are rejected.
Changes are picked up within one tick (or immediately with `iclean config` commands);
an invalid file keeps the previous config running and shows the error in `status`
and the menu.
