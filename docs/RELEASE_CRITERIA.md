# Release criteria for iClear 1.0 (pre-registered)

Committed on 2026-10-01, **before** any of the 1.0 measurements were taken. These
thresholds do not change after measurement. If a criterion is missed, the miss is
reported and the release stays a release candidate; the criterion is never lowered.
Results are recorded in [VALIDATION.md](VALIDATION.md) and the verdict in
[QUALITY.md](QUALITY.md).

Reference machine: Apple M3 Pro (Mac15,6), 18 GB, macOS 27.0.1. All lab work runs in
isolated homes and acts only on processes the lab started and registered (scope lock).

## Stage 1: lab gate (decides `v1.0.0-rc.1`)

All of C1-C7 and C10-C14 must pass. C8 and C9 decide whether a feature ships on or
off; they cannot fail the gate, but a feature whose rule is not met must ship off.

| # | Criterion | Threshold |
|---|---|---|
| C1 | Data safety | 0 fixture documents whose SHA-256 changed across all lab freeze/thaw and stash/pop cycles (documents are opened, never edited). |
| C2 | Crash recovery | 100/100 `kill -9` trials of the lab daemon while lab processes are frozen, and 50/50 trials while a stash is active: every registered lab process running (not stopped) and every app hidden by a stash unhidden within **2.0 s** of the kill. |
| C3 | Teardown | 0 lab processes left stopped after any test case. |
| C4 | Soak | ≥ 300 freeze/thaw cycles per fixture type for ≥ 3 types: a Chromium-family browser with a throwaway profile, an Electron app with throwaway user data, ≥ 1 native Apple app. Freeze durations randomized (0.2-20 s); ≥ 100 of each type's cycles under induced pressure. Result: 0 post-thaw hangs (no answer within 5 s) and 0 new crash reports from fixture processes. |
| C5 | Latency, no induced pressure | Thaw-to-responsive p99 ≤ **250 ms** per fixture type (fixtures ≤ 1 GB resident). |
| C6 | Latency, induced pressure | Thaw-to-responsive p99 ≤ **2000 ms** per fixture type after its memory was compressed or swapped under induced pressure. |
| C7 | Stash/pop | ≥ 50 cycles with ≥ 4 fixture apps: every window's origin and size within **4 points** of its pre-stash value, the previous frontmost app frontmost again, 0 crashes, 0 processes left stopped, 0 apps left hidden. |
| C8 | Automatic features (ship rule) | Each automatic trigger ships **on** only if N ≥ 20 paired runs (≥ 30 for Anti-Beachball) show the pre-set effect with the 95% bootstrap interval of the paired difference excluding 0, and no side-effect probe regresses by more than 5%. Call Mode: `ic-call-sim` timer-jitter p99 reduced by ≥ 20% under contention. Anti-Beachball mitigation: `ic-ui-probe` stall p99 reduced by ≥ 25%. Thermal trigger: thermal-state time above "fair" reduced by ≥ 20%. Otherwise the trigger ships **off** with its results documented. |
| C9 | Battery (ship rule) | Minute estimates always carry an "estimate" label and an interval. Auto-target ships **on** only if the median absolute error of predicted vs measured average power is ≤ **20%** over ≥ 3 real unplugged trials of ≥ 30 minutes each; otherwise it ships as experimental and off. |
| C10 | CI and coverage | CI green on every runner in the matrix; `ICCore` line coverage ≥ **90%**. |
| C11 | Test depth | Each feature (F1-F7 that ship, plus freeze/thaw, forecast and the shield ladder) has a continuous test of ≥ 2 minutes; one combined lab run of ≥ 60 minutes with all features on fixtures ends with 0 failures; every CLI command, menu action, config key and safety invariant is mapped in [TEST_MATRIX.md](TEST_MATRIX.md) to a test that exercises it, and anything without one is marked NOT TESTED and listed in the README. |
| C12 | Daemon overhead | Idle daemon CPU ≤ **0.5%** averaged over ≥ 10 minutes, resident memory ≤ **60 MB**. |
| C13 | Selftest | Full `iclear selftest` (≥ 2 minutes) reports no FAIL on the reference machine; any SKIP is permission-related and listed. |
| C14 | Release artifacts | Published assets: checksums match, every binary universal (arm64 + x86_64), `codesign -dv` works, `iclear --version` equals the tag, `iclear selftest --quick` and `iclear doctor` run from the artifact, and `iclear migrate` works from the artifact in an isolated home. |

Statistical meaning: 0 failures in 300 trials bounds the true failure rate below about
1% with 95% confidence (rule of three: 3/300). It does not show the rate is 0.

## Stage 2: 7-day soak (decides `v1.0.0`, evaluated in a later session)

| # | Criterion | Threshold |
|---|---|---|
| W1 | Elapsed time | ≥ 7 × 24 hours between the recorded soak start and the evaluation, checked from timestamps. |
| W2 | Awake time | ≥ 40 cumulative hours of the lab daemon running while the Mac was awake. |
| W3 | Volume | ≥ 5,000 freeze/thaw cycles and ≥ 300 stash/pop cycles in total. |
| W4 | Safety | 0 data-loss events, 0 processes left frozen (checked in every daily report and at the end), 0 new crash reports from lab fixture processes. |
| W5 | Overhead | p95 of the daily daemon CPU averages ≤ 0.5% and p95 resident memory ≤ 60 MB, for both instances. |
| W6 | Reporting | A daily report exists for every calendar day of the soak on which the Mac was awake. |
| W7 | Real-use Observe trace | Reviewed and reported: would-be freezes, would-be regret rate, call detections, forecast hits/false alarms/misses. The optional real-app Active trial is proposed only if the would-be regret rate is ≤ 20%. |

If any W criterion fails, `v1.0.0` is not tagged; a new `-rc` documents the failure.
