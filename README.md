# iClear (formerly iClean)

[![CI](https://github.com/urrra39/iClear/actions/workflows/ci.yml/badge.svg)](https://github.com/urrra39/iClear/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Development version on the way to 1.0** (last release: iClean 0.1.0 beta). Tested
> with synthetic test processes and on one Mac (Apple M3 Pro, macOS 27.0.1). Active mode
> on real apps is not yet validated. It starts in Observe mode, which only records what
> it would do. The project was renamed from iClean to iClear; see "Migrating from iClean".

iClear pauses idle background apps on a Mac that is running out of memory, and resumes
each one the moment you switch back to it. A paused app keeps its windows, tabs and
unsaved state. It just stops running, so macOS can compress or swap its memory instead
of fighting it for RAM. When memory pressure is normal, iClear does nothing.

**iClear never deletes your files.** It only pauses, resumes and advises. It removes no
caches, logs or downloads. Not affiliated with Apple Inc., and unrelated to cleaner
apps with similar names ([NAMING.md](docs/NAMING.md)).

[Oʻzbekcha](README.uz.md) · [How it works](docs/ARCHITECTURE.md) · [Safety](docs/SAFETY.md) ·
[Benchmarks](docs/BENCHMARKS.md) · [FAQ](docs/FAQ.md)

<p align="center"><img src="docs/images/menu-en.png" width="360" alt="iClear menu: Mac Health 100/100, memory normal, Observe mode, no apps paused"></p>

## When it helps, and when it does not

**Helps:** memory pressure is yellow or red, you have several heavy apps open that you
are not using (browsers, Electron apps, design tools, editors), and those apps keep
waking up in the background.

**Does not help:**

- Memory pressure is green. macOS already handles this well, and iClear stays idle.
- The app using the memory is the one you are working in.
- The memory belongs to something that must keep running (a build, a model, a VM,
  a call). iClear will not pause those.
- Apps that sit idle without waking up. macOS compresses those anyway, frozen or not.
- You are simply short of RAM for the work you do every day. `iclear advise` can tell
  you that once it has a week of data.

## What it does

- **Pause and resume** idle background apps under real pressure: the whole process
  tree, only apps with no visible window, only after every safety check passes.
  Resuming happens first thing when an app is activated.
- **`iclear why`**: "Why is my Mac slow right now?", a ranked, plain-language answer
  from measured data (pressure, swap, top apps, runaway CPU, heat, low disk, Low
  Power Mode).
- **Mac Health score** (0-100, formula in [ARCHITECTURE.md](docs/ARCHITECTURE.md)) in
  the menu bar, with a small swap timeline.
- **Runaway guard**: notices an app spinning the CPU or steadily growing in memory and
  tells you once. It never quits anything on its own.
- **Profiles**: Work, Battery Saver, Presentation and Dev, switching automatically on
  battery, mirroring or screen sharing, or on a schedule.
- **Focus Safe Mode**: no automatic action during calls, screen sharing, mirroring or
  fullscreen use.
- **Observe mode first**: it records what it *would* do until you switch it to Active.
- **Undo, Resume all, and an emergency hotkey** (Control-Option-Command-T, while the
  menu app runs). Resume all (menu or `iclear thaw --all`) works even if the daemon
  has crashed; it replays the freeze journal.
- **Daily/weekly digest** with measured numbers only, and suggestions such as "this app
  was idle 92% of the time, add it?" or "you reopened this one within a minute three
  times, exclude it?".
- **Explainable**: every action has reason codes; `iclear explain <app>` shows why an
  app was or was not paused.

The signature features, with what was measured for each and what ships on or off, are
in [SIGNATURE_FEATURES.md](docs/SIGNATURE_FEATURES.md): pressure forecast, regret-aware
decisions, habit statistics, connection and write guards, post-resume health check
with quarantine, trace replay (`iclear simulate`), workspaces (with an opt-in staged resume), and a
RAM right-sizing estimate.

## Measured results

From [BENCHMARKS.md](docs/BENCHMARKS.md). Apple M3 Pro, 18 GB, macOS 27.0.1, 2026-09-30.
Synthetic test processes, not real apps. Rows marked (1 run) are single observations.

| What | Result |
|---|---|
| Paused 512 MB process under induced pressure, resident memory | 519 MB → 6 MB (1 run) |
| Identical process that kept running, same pressure | 519 MB → 518 MB (1 run) |
| Resume signal to process running, 1 GB process (p50 / p95) | 0.03 / 0.05 ms |
| Resume with 512 MB to fault back in, under pressure | 80 ms (1 run) |
| Resuming 4 × 128 MB apps one after another vs all at once: first app usable / all four usable | 16.7 / 71.9 ms vs 37.7 / 40.1 ms (1 run; staged resume is therefore opt-in) |
| Daemon idle CPU (installed, 120 s window) | 0.35% |
| Daemon resident memory | 40 MB |

Not yet measured: memory reclaimed from real apps, real apps' resume latency, energy
savings, Intel Macs, 8 GB Macs.

## Permissions

| Permission | Required? | Used for | If denied |
|---|---|---|---|
| none | | pausing, resuming, `why`, health score, guards | everything works |
| Accessibility | optional | checking that a resumed app responds; measuring resume latency | hangs after resume are not detected; latency shows "not measured" |
| Input Monitoring | optional | experimental predictive resume (off by default) | nothing changes |
| Screen Recording | not used | | |

No root, no kernel extension, no SIP changes, no network access, no telemetry.

## Install

Built for macOS 13 and later, Apple Silicon and Intel (universal binary). Verified so
far: the build and full test suite on macOS 15.7 (Apple Silicon and Intel) and macOS
26.6 in CI, and on macOS 27.0.1 (Apple M3 Pro) locally. macOS 13 and 14 are not
verified.

**Release download.** The last published build is the
[iClean 0.1.0 pre-release](https://github.com/urrra39/iClear/releases/tag/v0.1.0), made
before the rename: its files and commands use the old names (`iclean`, `icleand`).
iClear builds will be published with the next release. Until then, build from source.

**From source:**

```sh
git clone https://github.com/urrra39/iClear.git && cd iClear
scripts/build-release.sh           # universal binaries, dist/iClear.app
cp -R dist/iClear.app /Applications/
```

A local build is ad-hoc signed: if macOS blocks the first launch, right-click the app,
choose Open, then confirm. The command-line
tools are in `dist/iclear-<version>/` and inside the app at `iClear.app/Contents/Helpers/`.

A Homebrew tap is planned but not published yet. Formula and cask templates are in
[`packaging/homebrew/`](packaging/homebrew/).

## Quickstart (60 seconds)

```sh
iclear install          # starts the per-user daemon, in Observe mode
iclear status           # what it sees and would do
iclear why              # why is my Mac slow right now?
iclear explain Chrome   # why an app was or was not paused
# ...use your Mac for a day, then:
iclear stats --days 1   # what it would have done, and its would-be regret rate
iclear mode active      # let it act
```

With the app, open iClear from Applications. Its menu shows the same information,
and "Start iClear" installs the daemon. In the app bundle, `iclear` lives in
`iClear.app/Contents/Helpers/`.

Emergency: **Control-Option-Command-T** or `iclear thaw --all` resumes everything.

## Safety model

In short: the freeze journal is written before every pause, and a watchdog process
resumes everything if the daemon dies, even from `kill -9`. Every signal re-checks
PID, start time and owner. A protected set (system, terminals, coding-agent hosts,
password managers, sync, VPN, input and accessibility tools) can never be paused by
any rule. Trees are paused all-or-nothing. Pauses are limited in time (4 h) and total
size (50% of RAM). Apps with audio, calls, downloads, network activity, dev-server
clients, recent writes or lock files are skipped. Each rule has a test; see
[SAFETY.md](docs/SAFETY.md).

## How it compares

These projects solve overlapping problems, and several did so earlier. From reading
their READMEs on 2026-09-30:

| Project | Approach | Difference from iClear |
|---|---|---|
| [ForceNap](https://github.com/omikun/ForceNap) | Suspends apps you pick whenever they lose focus, resumes on focus | Simple and direct. It suspends chosen apps regardless of memory pressure; iClear acts only under pressure and chooses apps itself |
| [Auto Pause Mac Apps](https://github.com/fazalrshah/auto-pause-mac-apps) | Menu-bar app to pause apps and reclaim RAM, plus a "Deep Sleep" that quits with state | Polished manual control and a quit-with-state mode iClear does not have. iClear is automatic, pressure-driven and guard-checked |
| [caproom](https://github.com/intelogroup/caproom) | Memory caps for commands; parks idle process trees with SIGSTOP, escalates to kill over the cap | Built for terminal jobs and agents with hard caps. iClear targets GUI apps and never kills |
| [ProcessX](https://github.com/avantigroupai/ProcessX) | Process/priority monitor; caps CPU by suspending and resuming | Focused on CPU and priority. iClear focuses on memory pressure |
| [GreenRAM](https://github.com/lwj1994/greenram) | Force-quits long-idle background apps over RAM/swap limits | Quitting frees all memory at the cost of state. iClear pauses and keeps state |
| [Canaryd](https://github.com/ThaddeusJiang/canaryd) | Watchdog for stalled services, Simulators, heat, idle memory; asks idle heavy apps to close | Broader developer-machine watchdog. iClear pauses instead of closing |
| [MemoryShield](https://github.com/MaatheusGois/MemoryShield) | Per-process memory history; can auto-kill over a threshold | History and alerts exist there too. iClear does not kill |
| [mac-memory-guard](https://github.com/TomGranot/mac-memory-guard) | Warns before a memory freeze, lets you quit apps one by one | Warning-first and human-in-the-loop. iClear acts on its own |

As of 2026-09-30, we did not find a pressure ETA forecast, regret-aware freezing,
connection/write guards before pausing, a post-resume quarantine or trace replay in
those projects or in our GitHub searches ([NOVELTY.md](docs/NOVELTY.md)). Not finding
something is not proof that it does not exist.

## Tested on

Real use, benchmarks and install/uninstall: one Mac so far (Apple M3 Pro, 18 GB, macOS
27.0.1). The automated test suite also passes on GitHub's macOS 15.7 (Apple Silicon and
Intel) and macOS 26.6 runners. iClear adapts its thresholds to
RAM size, disk type and battery, but "adapts to any MacBook" is not "tested on every
MacBook". Run `iclear doctor --report` and add your Mac to
[COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Migrating from iClean

iClear is the new name of iClean. If iClean 0.1.0 is installed, `iclear install` (or
`iclear migrate`) first resumes anything iClean had paused (through its daemon if it
still runs, then by replaying its freeze journal), and only then unloads and disables
the old LaunchAgent and copies your settings, state and traces. It stops without
changing anything if a process from the old journal is still paused. Old files stay
where they are until you run `iclear migrate --remove-old`. `iclear migrate --dry-run`
shows the plan first. Tested in isolated home directories with a simulated old install
(`MigrationTests`), including a crashed old daemon and a half-written journal.

## Uninstall

```sh
iclear uninstall --purge   # stops the daemon (resuming everything), removes the
                           # LaunchAgent and deletes ~/Library/Application Support/iClear
rm -rf /Applications/iClear.app
```

## More

[Architecture](docs/ARCHITECTURE.md) · [Safety](docs/SAFETY.md) ·
[Feasibility study](docs/FEASIBILITY.md) · [Decisions](docs/DECISIONS.md) ·
[Trace format](docs/TRACE_FORMAT.md) · [Quality](docs/QUALITY.md) ·
[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

MIT License. Not affiliated with Apple Inc. macOS and MacBook are trademarks of Apple
Inc. iClear is unrelated to the cache and disk cleaners with similar names
([NAMING.md](docs/NAMING.md)).
