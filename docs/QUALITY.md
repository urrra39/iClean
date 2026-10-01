# Quality self-assessment

Date: 2026-10-01. Scores are 1-10, with evidence, not adjectives. Anything below 9
lists what is missing.

| Dimension | Score | Evidence |
|---|---|---|
| Correctness | 8 | 103 unit and golden-trace tests (`ICCoreTests`) and 28 integration tests against real processes (`ICSystemTests`) pass on Apple M3 Pro / macOS 27.0.1. Line coverage of `ICCore`: 96.3% overall, 100% for `Policy`, `Journal`, `Health`, `Guards`, `Protection`, `Profiles`, `Runaway` (llvm-cov, 2026-09-30). |
| Safety | 9 | All 8 invariants in [SAFETY.md](SAFETY.md) have passing tests, including a real `kill -9` of the daemon with watchdog recovery, PID reuse, partial-tree rollback, corrupt journal and unwritable journal. Observe mode is the default. |
| UX | 7 | Menu with health, swap timeline, last action, mode/profile, Resume all, Undo, hotkey (rendered in English and Uzbek, `docs/images/`). `iclean why` and `explain` give plain-language answers. |
| Performance | 9 | Installed daemon idle: 0.35% CPU, 40 MB resident ([BENCHMARKS.md](BENCHMARKS.md)). Resume signal < 0.2 ms p99. Guard inspection 1.0 ms p50. |
| Docs | 8 | README (English, Uzbek), feasibility study, 30 recorded decisions, architecture with health formula and reason codes, safety table, benchmarks, signature-feature status, trace format, novelty audit, naming, FAQ. |
| Tests | 8 | 131 tests, golden traces in CI, adversarial cases listed in SAFETY.md. CI runs on macOS 15 (arm64), macOS 15 (Intel) and macOS 26. |
| Honesty | 9 | Every number traces to BENCHMARKS.md or FEASIBILITY.md; negative results kept (pre-thaw no benefit, staged thaw slower for the last app, first daemon build over its CPU target); unmeasured items say "not yet measured". |

## Known gaps

**Correctness (8):**
- Real-app behaviour (browsers, Electron) has only been observed in Observe mode, never
  frozen in Active mode on a daily-use machine.
- Screen sharing is detected by process name only.
- The `Commands` IPC handler and the menu app have no unit tests; they are covered only
  by `ipcRoundTrip` and manual rendering.

**UX (7):**
- The profile picker shows the active profile, not "Automatic", when no manual profile
  is set.
- No onboarding screen explains Observe mode on first launch beyond the status line.
- Thaw latency of real apps needs Accessibility, and there is no in-app prompt flow
  beyond a link to Settings.

**Docs (8):**
- Architecture docs are English only; only the README is translated.
- No man page yet (shell completions exist: `iclean completions zsh|bash|fish`).

**Tests (8):**
- Hang-after-resume is tested only at the decision level (needs Accessibility).
- Sleep/wake is tested by injecting the event, not by a real lid close.
- `swift format lint` reports style findings; CI runs it as report-only.
- Signature features S1, S3 and S8 have no evaluation on real traces yet
  ([SIGNATURE_FEATURES.md](SIGNATURE_FEATURES.md)).

**Not yet done from the original plan:** P1 disk-headroom advisory, dev-load handling
(Simulators, Gradle and Kotlin daemons, orphaned node processes), thermal/battery
advisor, Shortcuts/App Intents (P2). Notarized releases (needs a Developer ID).

## Secret scanning

gitleaks was **not** run: Homebrew is not installed on the maintainer's Mac, and
installing it needs an administrator password. Instead, every commit in the history
(14 at the time) and the working tree were scanned with a regular-expression pass
covering GitHub, AWS, Slack, Google, GitLab and npm token formats, private-key
blocks, and `api_key`/`secret`/`password` assignments. Result on 2026-10-01: 0 hits.
Running gitleaks (`gitleaks detect --log-opts=--all`) remains a to-do.
