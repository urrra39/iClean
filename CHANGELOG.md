# Changelog

## Unreleased (1.0 in progress)

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
