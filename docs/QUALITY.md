# Quality self-assessment

Date: 2026-10-01, version 0.1.0 (beta). Scores are 1-10, with evidence, not
adjectives. Anything below 9 lists what is missing.

| Dimension | Score | Evidence |
|---|---|---|
| Correctness | 7 | 103 unit and golden-trace tests and 28 integration tests against real processes pass locally (macOS 27.0.1) and in CI on macOS 15.7 arm64, macOS 15.7 Intel and macOS 26.6 ([run 36811882428](https://github.com/urrra39/iClean/actions/runs/36811882428)). `ICCore` line coverage 96.3%; 100% for `Policy`, `Journal`, `Health`, `Guards`, `Protection`, `Profiles`, `Runaway`. Capped at 7 because Active mode has never run on real apps. |
| Safety | 9 | All 8 invariants in [SAFETY.md](SAFETY.md) have passing tests, including a real `kill -9` of the daemon with watchdog recovery, PID reuse, partial-tree rollback, corrupt journal and unwritable journal. Observe mode is the default. |
| UX | 7 | Menu with health, swap timeline, last action, mode/profile, Resume all, Undo, hotkey, in English and Uzbek (`docs/images/`). `iclean why` and `explain` give plain-language answers. |
| Performance | 9 | Installed daemon idle: 0.35% CPU, 40 MB resident ([BENCHMARKS.md](BENCHMARKS.md)). Resume signal < 0.2 ms p99. Guard inspection 1.0 ms p50. |
| Docs | 8 | README (English and Uzbek) with beta banner, feasibility study, recorded decisions, architecture, safety, benchmarks, signature-feature status, trace format, novelty audit, naming, FAQ, dogfooding plan. |
| Tests | 8 | 131 tests on three CI runners plus local; golden traces; adversarial cases listed in SAFETY.md; swift-format lint is blocking in CI. |
| Honesty | 9 | Every number traces to BENCHMARKS.md or FEASIBILITY.md; negative results kept (pre-thaw no benefit, staged thaw slower for the last app, first daemon build over its CPU target); version is 0.1.0 beta; "not validated" list below. |

## Not validated

These are designed and unit- or integration-tested with synthetic inputs, but have
**not** been validated on real use:

- Active mode freezing real apps (browsers, Electron, design tools) on a daily-use Mac.
  See [DOGFOOD.md](DOGFOOD.md).
- Memory actually reclaimed from real apps, and their resume latency (needs
  Accessibility).
- Focus Safe Mode detection of real calls (camera, microphone), screen sharing (by
  process name only), mirroring and fullscreen.
- Automatic profile switching on real battery, mirroring and schedule events.
- Sleep/wake and unlock thaw on a real lid close (tested by injecting the event).
- Hang-after-resume detection (decision logic tested; the probe needs Accessibility).
- Forecast (S1) lead time and false-alarm rate, habit (S3) hit rate and the RAM advisor
  (S8) on real traces.
- macOS 13 and 14; Intel hardware outside CI; 8 GB Macs; rotational disks.
- The emergency hotkey (Control-Option-Command-T) is not covered by an automated test.
- Notarized distribution (releases are ad-hoc signed).

## Known gaps

- The menu's profile picker shows the active profile, not "Automatic", when no manual
  profile is set.
- The forecast summary in the menu ("stable", "yellow in ~N min") comes from the
  daemon in English, even in the Uzbek menu.
- No first-launch onboarding beyond the status line; no in-app Accessibility prompt
  beyond a link to Settings.
- Architecture docs are English only.
- No man page (shell completions exist).
- The `Commands` IPC handler and the menu app have no dedicated unit tests (covered by
  `ipcRoundTrip` and manual rendering).
- Not built from the original plan: P1 disk-headroom advisory, dev-load handling,
  thermal/battery advisor, Shortcuts/App Intents.

## Release 0.1.0

[Pre-release](https://github.com/urrra39/iClean/releases/tag/v0.1.0) built by the
release workflow from tag `v0.1.0`. Verified after download: SHA256 checksums match
`SHA256SUMS.txt`; all six binaries are universal (`x86_64 arm64`); the app's ad-hoc
signature verifies (`codesign --verify --deep --strict`, hardened runtime flag set);
`iclean --version` prints 0.1.0 and `iclean doctor` runs from both the tarball and the
app's `Helpers` folder.

## Secret scanning

gitleaks was **not** run: Homebrew is not installed on the maintainer's Mac, and
installing it needs an administrator password. Instead, every commit in the history
and the working tree were scanned with a regular-expression pass covering GitHub,
AWS, Slack, Google, GitLab and npm token formats, private-key blocks, and
`api_key`/`secret`/`password` assignments. Result on 2026-10-01 (14 commits at the
time): 0 hits. Running gitleaks (`gitleaks detect --log-opts=--all`) remains a to-do.
