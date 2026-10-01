# Release criteria for iClear 1.0 (pre-registered)

Committed on 2026-10-01, **before** any of the 1.0 measurements were taken. These
thresholds do not change after measurement. If a criterion is missed, the miss is
reported and the release stays a release candidate; the criterion is never lowered.
Results are recorded in [VALIDATION.md](VALIDATION.md) and the verdict in
[QUALITY.md](QUALITY.md).

**Amendment (2026-10-01, owner decision, [DECISIONS.md](DECISIONS.md) #36).** Made
before any soak data existed and before any side-effect test ran. It changes two
things and nothing else: the 7-day soak (stage 2) moves from "required for v1.0.0" to
"reported after release", and a side-effect gate (stage 3) is added. **Release rule:**
v1.0.0 is tagged only when stage 1 and stage 3 both pass; if any must-pass criterion
of either fails, the release is `v1.0.0-rc.N` and the failures are listed.

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

## Stage 2: 7-day soak (reported after release; not required for `v1.0.0`)

| # | Criterion | Threshold |
|---|---|---|
| W1 | Elapsed time | ≥ 7 × 24 hours between the recorded soak start and the evaluation, checked from timestamps. |
| W2 | Awake time | ≥ 40 cumulative hours of the lab daemon running while the Mac was awake. |
| W3 | Volume | ≥ 5,000 freeze/thaw cycles and ≥ 300 stash/pop cycles in total. |
| W4 | Safety | 0 data-loss events, 0 processes left frozen (checked in every daily report and at the end), 0 new crash reports from lab fixture processes. |
| W5 | Overhead | p95 of the daily daemon CPU averages ≤ 0.5% and p95 resident memory ≤ 60 MB, for both instances. |
| W6 | Reporting | A daily report exists for every calendar day of the soak on which the Mac was awake. |
| W7 | Real-use Observe trace | Reviewed and reported: would-be freezes, would-be regret rate, call detections, forecast hits/false alarms/misses. The optional real-app Active trial is proposed only if the would-be regret rate is ≤ 20%. |

The soak results are published after the release as a follow-up. A failed W criterion
is reported in the README and fixed in a later release; it is never hidden.

## Stage 3: side-effect gate (added by the amendment; required for `v1.0.0`)

Measured with simulators and lab fixtures only (no personal accounts): `ic-chat-sim`,
`ic-media-sim`, and Chrome with a throwaway profile on local pages. All must pass.

| # | Criterion | Threshold |
|---|---|---|
| E1 | Data loss | 0 data-loss events (documents, downloads, form input, delivered messages) across the side-effect tests. |
| E2 | Guards | Guards block 100% of freeze attempts made during active audio output, a call (microphone or camera) and a running download in the tests. |
| E3 | Connections | 0 connection states that stay broken after thaw in the Chrome and simulator tests; otherwise the app class affected ships protected by default. |
| E4 | Disclosure | Every observed side effect is fixed, mitigated by a default, or documented in the README's "Known side effects"; anything that cannot be fixed becomes a class protected by default.

## Stage 4: v1.1 (added by amendment 2; required for `v1.1.0`)

**Amendment 2 (2026-10-02, owner decision, [DECISIONS.md](DECISIONS.md) #37).** Made
before any v1.1 measurement (no spike, lab run or trace analysis for Auto-Context Stash
or the leak trend had been run). It adds this stage and changes nothing above.
**Release rule:** v1.1.0 is tagged only when every must-pass criterion below passes and
the stage 1 regression subset (C1, C2, C3, C10, C12, C13, C14) still passes on the
v1.1 build; otherwise the release is `v1.1.0-rc.N` with the failures listed. Lab work
starts after the 7-day soak's wrap-up (not before 2026-10-09 01:30 local time).

### Auto-Context Stash (`iclear context`, `iclear hook`)

| # | Criterion | Threshold |
|---|---|---|
| X1 | Shell-hook overhead | Added time per prompt or directory change, measured inside the shell over ≥ 1,000 events per shell (zsh and bash on the reference machine), daemon running and not running: **p95 ≤ 5 ms**. Shells that cannot be tested here (fish) are listed as not tested. |
| X2 | Wrong-app stash | **0** apps stashed that were not in the leaving context's group, over ≥ 200 scripted switches between ≥ 3 contexts of lab fixture apps (scope-locked). |
| X3 | Enter-to-usable latency | Reported as p50/p95 (N ≥ 100) from the end of the dwell time until every app of the new context is shown and the frontmost app is restored; must-pass **p95 ≤ 3 s**. Never described as instant. |
| X4 | False triggers | **0** switches over ≥ 200 scripted events that must not switch: moves between subdirectories of one context, `cd /tmp` and `cd ~` round trips, a context left and re-entered within the dwell time, switches inside the cooldown. |
| X5 | Undo | **50/50** `iclear context undo` runs restore the previous state: the same apps paused or running, hidden or shown, and the same frontmost app. |
| X6 | Crash mid-switch | **50/50** `kill -9` trials of the lab daemon during a switch: every lab process running and every app hidden by the switch shown again within 2.0 s. |
| X7 | Defaults | Suggest mode by default; automatic switching only per context and only in Active mode; Observe mode records "would switch" and does nothing else (tests). |
| X8 | Real use (reported, not a gate) | After the soak, with the hook in suggest mode on the owner's terminal: suggestions shown, accepted and dismissed, reported as counts. |

### Leak trend (`iclear leaks`)

Evaluated on synthetic process trees (`ic-hog`) with known growth, noise, step changes
and sawtooth caches, at least 30 growing and 30 non-growing trees, sampled by the daemon
as in normal use.

| # | Criterion | Threshold |
|---|---|---|
| L1 | Recall | Of trees growing ≥ 50 MB/h for ≥ 3 h while not in use, **≥ 90%** flagged within 3 h of the minimum data (2 h, 12 samples). |
| L2 | Precision | Of flagged trees, **≥ 90%** truly growing (≥ 10 MB/h). |
| L3 | False alarms | Flags on non-growing trees (flat with noise, single step, sawtooth caches): **≤ 0.05 per tree per day**. |
| L4 | Rate and ETA error | Reported as distributions (N ≥ 30); must-pass: median absolute error of the growth rate **≤ 25%** of the true rate. |
| L5 | Notifications (ship rule) | Leak notifications ship **on** only if L1-L4 pass **and** the retrospective check on the soak's 7-day Observe trace meets: of trees flagged there, ≥ 80% have a footprint 1 h later within ±30% (or ±100 MB) of the predicted value. Otherwise `iclear leaks` and the menu list only. |
| L6 | Never acts by itself | No quit without an explicit preview and confirmation; never a force-kill (tests). |

### Optional research spikes (nothing ships on these)

Each is stopped, and reported as stopped, if its kill criterion holds:
(a) thermal: throughput retention under sustained synthetic load with and without
same-user background load, public thermal state only; kill if the gain is below 10% or
the load cannot be run safely; (b) swap: whether thawing a previously frozen and pressured
fixture lowers `vm.swapusage` without raising pressure; kill if no drop of ≥ 10% within
10 minutes; (c) Chrome renderer stop in a throwaway profile, documentation only.
