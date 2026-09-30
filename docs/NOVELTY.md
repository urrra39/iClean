# Novelty audit

Date: 2026-09-30. Method: GitHub repository search (`gh search repos`), web search,
and reading the README of every close match. **"Not found" is not proof of
absence.** It only means these searches, on this date, did not turn anything up.
iClean does not claim to be first at anything.

## Closest projects (verified by reading their READMEs)

| Project | What it does (from its README) |
|---|---|
| [omikun/ForceNap](https://github.com/omikun/ForceNap) | Suspends chosen apps when they lose focus and resumes them on focus. Notes that suspended apps show a beachball and "Not responding", and that suspend "keeps data in memory". |
| [fazalrshah/auto-pause-mac-apps](https://github.com/fazalrshah/auto-pause-mac-apps) | Menu-bar app that pauses apps you are not using so macOS can reclaim their RAM and resumes them. Also has a "Deep Sleep" mode that quits apps while preserving state. |
| [intelogroup/caproom](https://github.com/intelogroup/caproom) | Memory caps for commands, plus SIGSTOP "parking" of idle process subtrees, escalating to TERM/KILL over the cap. Aggregates whole process trees. |
| [avantigroupai/ProcessX](https://github.com/avantigroupai/ProcessX) | Process and priority monitor with one-click reprioritisation. A "Cap" action throttles CPU by suspending and resuming an app. |
| [lwj1994/greenram](https://github.com/lwj1994/greenram) | Menu-bar app that force-quits long-idle background apps under RAM or swap limits, with a whitelist and whole-tree memory accounting. |
| [ThaddeusJiang/canaryd](https://github.com/ThaddeusJiang/canaryd) | Local watchdog for stalled services, forgotten Simulators, heat and idle memory. Requests a graceful close of idle heavy apps and never escalates to SIGKILL. |
| [MaatheusGois/MemoryShield](https://github.com/MaatheusGois/MemoryShield) | Menu-bar monitor with per-process memory history that can auto-kill apps over a sustained threshold. |
| [TomGranot/mac-memory-guard](https://github.com/TomGranot/mac-memory-guard) | Bash watchdog that warns before memory pressure becomes a freeze and lets you quit the biggest apps one at a time. |

Known facts, stated so nobody reads them as new: process memory history, memory-growth
alerts, idle-app suspension, SIGSTOP/SIGCONT freezing, whole-tree accounting and
pressure-triggered cleanup already exist in the projects above.

## Per feature

| Feature | Queries used | Result on 2026-09-30 |
|---|---|---|
| S1 Pressure forecast (ETA to warning) | "memory pressure forecast macos", "memory pressure prediction", "macos memory forecast" | One unrelated repository with no description ("ai-memory-pressure-prediction"). mac-memory-guard warns *before* a freeze using thresholds, not a trend ETA. No ETA-to-warning tool found. |
| S2 Regret-aware freezing | "freeze regret macos app suspend" | Nothing found |
| S3 Habit-based return prediction | "habit prediction app switch prethaw", "app switch prediction markov macos" | Nothing found |
| S4 Connection/Write guard before freezing | "SIGSTOP socket guard freeze skip established connection" | Nothing found. caproom's parking predicate checks idleness and session leadership, not sockets or files. |
| S5 Post-thaw health check and quarantine | "quarantine app after resume crash macos suspend" | Nothing found |
| S6 Trace replay of a freeze policy | "simulate replay trace memory policy macos" | Nothing found |
| S7 Staged thaw / workspaces | "staged thaw resume apps swap stampede" | Nothing found |
| S8 RAM right-sizing from local history | "RAM upgrade advisor macos memory history" | Nothing found |

Queries returning nothing were also rerun with shorter wording ("app suspend macos
memory", "freeze idle apps macos", "sigstop idle apps", "mac memory guard"). These
found only mac-memory-guard, which is listed above.

## What the README may say

Only dated, evidence-backed statements of the form "as of 2026-09-30, we did not find
X in: ForceNap, auto-pause-mac-apps, caproom, ProcessX, GreenRAM, Canaryd,
MemoryShield, mac-memory-guard", always followed by "not found is not proof of
absence".
