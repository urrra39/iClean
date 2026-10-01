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
- **Power and heat.** Every phase except the battery trials ran on AC power (the Mac
  was plugged in at 14:24 on 2026-10-01). Each result lists the power source and
  thermal state sampled during the run (once per cycle, pair or minute).

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
