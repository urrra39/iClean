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
