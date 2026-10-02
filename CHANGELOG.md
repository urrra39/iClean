# Changelog

## Unreleased (v1.1, in development; not validated)

- **Auto-Context Stash** (`iclear hook zsh|bash|fish|git`, `iclear context ...`): app
  groups that follow the project your terminal is in. Suggests a switch after 20 s in
  another project (automatic only for contexts that opt in, in Active mode; Observe mode
  records "would switch"). A switch stashes the leaving group and pops the new one as one
  transaction: apps both groups use and apps that cannot be paused stay running, and a
  hard block stops the switch. Subdirectory moves, `cd ~` and `/tmp` do not switch; a
  5-minute cooldown follows each switch; `iclear context undo` reverses it;
  `iclear context suggest` proposes apps from what you brought to the front while
  working in a project. Menu: a Switch / Not now row.
- **Leak trend** (`iclear leaks`, menu: Growth): steady memory growth of apps that are
  not in use, from Theil-Sen and Mann-Kendall over up to 3 hours, with an interval, a
  confidence level and an ETA to the next whole gigabyte. A trend, not a diagnosis.
  `iclear leaks quit <app>` previews, and with `--yes` asks the app to quit through its
  own Quit. Notifications are off by default (`leaks.notify`).
- New config keys: `contexts`, `context.dwellSeconds`, `context.cooldownMinutes`,
  `leaks.notify`, `leaks.minHours`, `leaks.minSamples`, `leaks.minRateMBPerHour`.
- `iclear selftest` adds a context switch between two probe apps in an isolated daemon
  and the leak trend on synthetic series.
- `ic-hog --profile` shapes a footprint over time (growth, noise, a step, a sawtooth
  cache, a faster clock) for the leak-trend lab.
- The trace retention fix shipped in 1.0.1 (below).
- Release criteria: stage 4 (X1-X8, L1-L6) added before any v1.1 measurement
  (amendment 2).

## 1.0.1 (2026-10-02)

- **Fix: traces could be wiped at the size cap.** Trace files were deleted in name order,
  and a day's current file (`day.jsonl`) sorts before its rotated `day.jsonl.1`, so when
  the traces passed `trace.maxMB` the file still being written was deleted first and the
  rest could follow. Reading also returned a rotated file's older records after the newer
  ones. Files are now handled oldest first (a day's `.1` before the current file), and
  the newest file is kept. Two tests cover it; before them no test covered the trace
  files. Found on 2026-10-02 while preparing the soak's trace analysis.
- Known limit, unchanged: with many apps a day of traces can exceed the 20 MB default
  (`trace.maxMB`), so `iclear simulate --since 7d` and `iclear advise` may see less than
  a week of data.
- Nothing else changed. Lab and validation results in the docs are from 1.0.0.

## 1.0.0 (2026-10-02)

- **Renamed from iClean to iClear.** CLI `iclear`, daemon `icleard`, app iClear, bundle
  ID and LaunchAgent label `io.github.urrra39.iclear`, data in
  `~/Library/Application Support/iClear/`. `iclear install` and `iclear migrate`
  resume anything iClean had frozen (old daemon first, then the old journal), unload
  and disable the old LaunchAgent only after that succeeds, and copy settings, state
  and traces. Old files are deleted only with `iclear migrate --remove-old`.
- `ICLEAR_HOME` now names a home directory (iClear uses `Library/...` under it), and
  `ICLEAR_INSTANCE` runs a separate, named instance.
- Staged thaw is off by default (`stagedThaw`), see docs/SIGNATURE_FEATURES.md.
- **Workspace Stash** (`iclear stash <name>`, `iclear pop`): hides and pauses a set of
  apps in one step and brings them back with the same windows and the same frontmost
  app. Hard blocks for audio, microphone, power assertions and call apps on camera;
  soft risks need `--include`; disk headroom is checked first. Stashes live in the freeze
  journal, so a crash, logout or shutdown resumes and unhides them. Activating a stashed
  app pops just that app. Stashes expire after 24 h (`stash.maxAgeHours`).
- **`iclear selftest`**: about 2 minutes of checks on this Mac with iClear's own test
  processes (signals, watchdog recovery, hide/unhide bounds, GUI resume latency, stash,
  pressure sensor, call detection, battery readings, shield, stall probe, migration,
  permissions). `--quick` takes about 12 s; `--report` prints a block to paste into an
  issue.
- **Battery estimates** (`iclear battery`): minutes gained by pausing an app, as a range
  labelled "estimate", from per-process energy counters and the battery's own reading,
  checked against later readings. `iclear battery target <time>` is experimental and
  off (`battery.targetEnabled`).
- **Call Mode** (`callMode`, off by default): during a call, lowers the priority of
  other busy apps, and pauses eligible idle apps only if that did not reduce the
  measured interference. The call's own apps are never touched.
- **Anti-Beachball forensics** (`iclear beachball`): with Accessibility, records when
  the frontmost app stops answering for more than 500 ms and what the Mac was doing
  (paging, disk, CPU, heat). Mitigation (`antiBeachball.mitigation`) is off.
- **`iclear before <app>`**: estimate of whether launching an app pushes memory into
  yellow, from this Mac's history (needs 30 samples; otherwise it says so).
- Priority-band and hidden-state changes are journaled with their previous value and
  restored by recovery, the watchdog and shutdown.
- The menu shows stashes, a battery line and Battery, Stalls and Calls views;
  ⌃⌥⌘S / ⌃⌥⌘P stash and pop when `stash.hotkeys` is on.
- `ICLEAR_LAB=1` (scope lock) and `ICLEAR_OBSERVE_ONLY=1` for lab and observation
  instances.
- **App classes** and `iclear compat <app>`: chat, mail, calendar and media apps are
  Tier S by default; no app is paused while it plays audio or uses the microphone, or
  for `audioCooldownMinutes` (10) after; browsers wait `browserIdleFactor` (2×) longer
  and need wake windows of at least 30 s. Rule packs in `packaging/rules/`.
- Fixed, found by the side-effect lab: a direct `iclear freeze` used audio and
  microphone readings up to 30 s old; Chrome's audio and microphone readings flicker
  between samples (now three readings are combined and the cooldown starts at the first
  silent one); with two copies of an app running, launchd-started helpers were claimed
  by both; `iclear pop --all` with nothing stashed reported an error.
- Fixed: test processes started by the selftest and lab kept a CPU core busy after they
  exited (a pipe handler spun at end of file).
- Fixed, found by the stash lab: hiding the frontmost app first let macOS activate an app
  still waiting to be stashed, which popped it again (apps are now hidden back to front,
  and activations in the first 2 s of a stash are ignored); pop could leave a different
  app in front than before the stash (it now confirms the restored app stays in front
  for 0.5 s, and keeps the app the user is in when the stash did not include the old front app or
  the user already brought it back).
- Fixed, found by the overhead measurement: call signals were polled every second even
  with every shield off; now every 5 s unless a shield can act (0.48% of one core idle).
- Release criteria amended once by owner decision (DECISIONS.md #36): the 7-day soak is
  reported after release, and a side-effect gate is required for 1.0.0.

## 0.1.0 (beta)

First version, released under the name iClean.

- Daemon (`icleand`), command-line tool (`iclean`) and menu-bar app.
- Pauses idle background apps (whole process trees) under memory pressure and resumes
  them on activation, with a crash-safe journal, a watchdog process, a protected set,
  PID-reuse checks and all-or-nothing tree freezes.
- Observe mode by default.
- `why`, `explain`, `stats`, `doctor`, `simulate`, `trace export`, `advise`,
  workspaces, profiles, Focus Safe Mode, runaway guard, Mac Health score.
- Connection and write guards, post-resume health check with quarantine, regret
  tracking, habit statistics, workspaces.
- Forecast-driven actions, pre-resume and staged resume ship off (see
  [docs/SIGNATURE_FEATURES.md](docs/SIGNATURE_FEATURES.md)).
- English and Uzbek menu.
