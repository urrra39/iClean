# Novelty audit

Date: 2026-09-30. Method: GitHub repository search (`gh search repos`), web search,
and reading the README of every close match. **"Not found" is not proof of
absence.** It only means these searches, on this date, did not turn anything up.
iClear does not claim to be first at anything.

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

## 1.0 audit (2026-10-01)

Method as above (GitHub search, web search, reading READMEs and product pages). Some
GitHub searches hit the search API's rate limit; those queries were repeated as web
searches.

### Related projects (verified today)

| Project | What it does (from its README or site) |
|---|---|
| [Gabrielnion/AppHalt](https://github.com/Gabrielnion/AppHalt) | "A simple pause button for Mac apps": pause and resume background apps from the menu bar; states it is not a cleaner and deletes nothing. |
| [exadeci/mac_freeze](https://github.com/exadeci/mac_freeze) (MacFreeze) | Freezes selected apps after a configurable inactivity delay (glob patterns per app), unfreezes on switch-back and on quit. |
| [actuallymentor/wintertime-mac-background-freezer](https://github.com/actuallymentor/wintertime-mac-background-freezer) | Freezes apps that are not in the foreground to save battery, with a "panic button" that unfreezes everything. |
| [omikun/ForceNap](https://github.com/omikun/ForceNap) | Suspends chosen apps when not in focus (release builds published from MyAppNap). |
| [ShiftPlus](https://shiftplus.app/blog/shift-mac/) | Workspace switcher: closes irrelevant apps, opens the right ones with browser profiles, URLs and window layout, restores after restart. |
| [ThaddeusJiang/canaryd](https://github.com/ThaddeusJiang/canaryd) | Watchdog that confirms hangs (for example a hung helper) and restarts only the stale instance; also watches heat and idle memory. |
| [gyorgysh/keepresso](https://github.com/gyorgysh/keepresso) | Keep-awake app with triggers including "camera or microphone is in use", optionally scoped to one app. |
| [WattMate](https://wattmateapp.com/) | Per-app watts converted into battery minutes, and a measurement of what quitting an app actually gave back about 2 minutes later. |
| [TurtleBar](https://www.turtlebar.app/guides/macbook-battery-usage-by-app) | Ranks the apps using the most power and shows what they cost in runtime. |
| [QuietMeet](https://apps.apple.com/us/app/quietmeet-auto-pause-music/id1616212598?mt=12) | Detects video calls and pauses or resumes Music playback. |
| [ColinIanKing/powerstat](https://github.com/ColinIanKing/powerstat) | Linux: measures system power from battery stats or RAPL, with statistics over a run. |

Not found under the names given: "Stash" by StarchyBomb (web search found only browser
tab-stash extensions such as Tab Stash and Stash by Commonplace) and "Linux PowerStats"
as a per-app minutes tool (powerstat above is system-wide).

**Related, deliberately not built:** sleep and overnight-drain diagnosis already has
dedicated tools, for example [napwatch](https://github.com/Tuguberk/napwatch) (dark
wakes, Power Nap, live drain), Wake, DarkWake and LidGuard.

### Per feature

| 1.0 feature | Queries | Closest found on 2026-10-01 |
|---|---|---|
| Workspace stash (hide and freeze a set of apps, pop them back) | "freeze apps workspace stash macos", "suspend apps hide workspace macos", "app stash macos", "workspace freeze mac" | ShiftPlus switches workspaces by closing and reopening apps; AppHalt, MacFreeze, wintertime and ForceNap pause apps one by one. No tool found that freezes a named group in place and restores window positions. |
| Battery minutes and "what did it give back" | "battery minutes per app macos estimate", "battery remaining time per app pause", web search | **WattMate already does both**: watts to minutes per app, and a measured before/after receipt. TurtleBar shows runtime cost per app. iClear's version is not new. |
| Call Mode (protect a call by deprioritizing or pausing other work) | "video call protect background apps cpu macos", "meeting mode deprioritize background apps", "call mode macos", web search | Keepresso uses camera/mic-in-use as a keep-awake trigger; QuietMeet pauses music during calls. No tool found that lowers other apps' priority during a call. |
| Anti-Beachball forensics | "beachball stall detector macos", "spinning wheel diagnose macos app hang", web search | Canaryd confirms and recovers hangs of specific helpers; general advice points to Activity Monitor and Console. No tool found that records stall causes for the frontmost app. |
| Pre-launch advisor | "launch app memory pressure predict" | Nothing found. |
| Unsaved-work guard | "unsaved documents detect accessibility macos" | Nothing found. |
| Selftest of freeze/resume on the user's Mac | "selftest suspend resume compatibility macos" | Nothing found. |

"Not found" is not proof of absence. README claims follow the form "as of 2026-10-01,
we did not find X in: …".

## Prior-art update (2026-10-02)

Re-read on 2026-10-02 (READMEs, product pages, crates.io API, GitHub search):

| Project | What it does (from its README or site) | Difference |
|---|---|---|
| [AppHalt](https://apphalt.app/) ([README](https://github.com/Gabrielnion/AppHalt)) | Pause and resume chosen apps from the menu bar, windows and documents kept; Pro ($9.99 one-time) adds auto-pause after a user-set idle period, groups and a never-pause list. Not described as open source. | Manual or idle-driven; iClear is pressure-driven, guard-checked, Observe-first. |
| [MacFreeze](https://github.com/exadeci/mac_freeze) | SIGSTOP/SIGCONT freezing of apps matching glob patterns after a per-app delay; unfreezes everything when disabled or quit. Swift, macOS 10.14+. | No memory-pressure trigger or guards. |
| [wintertime](https://github.com/actuallymentor/wintertime-mac-background-freezer) | Freezes listed apps when they are not in focus (its README says it runs `pkill ... -f REGEX` for each item), panic button; "Tested on High Sierra 10.13.5". | Focus-driven, battery-oriented. |
| [ShiftPlus](https://shiftplus.app/blog/shift-mac/) | Hotkey (or menu) workspace switch: "closes or hides" apps outside the workspace, launches the rest, browser profiles, Spaces, terminal variables; 14-day trial. Not triggered by directory changes. | Closes and reopens instead of pausing in place. |
| [ContextResume](https://github.com/yigitbozyaka/ContextResume) | Per-branch developer context (git state, last failing command, intent) through a shell prompt hook that "calls Node only when your branch changes"; does not manage apps. | Closest to Auto-Context's trigger (shell hook on branch change), but restores notes, not apps. |
| [direnv](https://direnv.net/) | Loads and unloads environment variables per directory through a shell hook. | Adjacent: environment, not apps. Its hook model informs `iclear hook`. |
| [SceneShift](https://tandukuda.github.io/SceneShift/) | Windows 10+ terminal tool: kill, suspend, resume or relaunch presets of apps; session history with undo. | Windows only. |
| [amphetamine](https://github.com/GriffinCanCode/amphetamine) (crate 0.1.2, 2026-08) | "Reclaim memory and win scheduler contention on Apple Silicon, safely": quit requests via the app's own terminate (no force-kill), `nice` demotion only from nice 0 with a verified restore path and `amph restore`, notes that swap drains only as the owning processes exit, deletes old caches under `~/Library/Caches` and `~/Library/Logs`. | Quits and deletes caches; iClear pauses and does not delete files. |
| Chrome ([Energy Saver freezing](https://developer.chrome.com/blog/freezing-on-energy-saver), [Memory Saver](https://support.google.com/chrome/answer/12929150)) | From Chrome 133, CPU-intensive tabs hidden and silent for over five minutes are frozen (Page Lifecycle "frozen") under Energy Saver; Memory Saver deactivates inactive tabs, which reload on return. | Inside one browser; iClear acts on whole apps. |

Still not found under the name given: "Stash" by StarchyBomb (no GitHub user or
repository by that name; web results are unrelated apps called Stash).

As of 2026-10-02, we did not find a pressure ETA forecast, regret-aware freezing,
connection/write guards before pausing, a post-resume quarantine or trace replay in the
projects above. Not found is not proof of absence.

## What the README may say

Only dated, evidence-backed statements of the form "as of 2026-09-30, we did not find
X in: ForceNap, auto-pause-mac-apps, caproom, ProcessX, GreenRAM, Canaryd,
MemoryShield, mac-memory-guard", always followed by "not found is not proof of
absence".
