# Safety model

iClean stops other people's programs. The rules below are what make that acceptable,
and each has a test that must pass before a release.

| # | Invariant | How | Test |
|---|---|---|---|
| 1 | Nothing stays frozen if the daemon dies | Journal written (fsync + rename) **before** every SIGSTOP; recovery on start; SIGTERM/SIGINT/SIGHUP and normal exit thaw all; a watchdog process in its own session replays the journal on daemon exit (kqueue `NOTE_EXIT`); `iclean thaw --all` and the menu's "Resume all" work without the daemon | `watchdogThawsAfterDaemonIsKilled` (real `kill -9`), `daemonStartRecoversJournal`, `cliThawAllWorksWithoutDaemon`, `wakeAndShutdownThawEverything` |
| 2 | PID reuse can never redirect a signal | Every signal re-checks PID + start time (`PROC_PIDTBSDINFO`) + owner uid | `pidReuseGuardNeverSignalsAnotherProcess`, `recoveryNeverSignalsReusedPIDs`, `recoveryThawsOnlyExactIdentities` |
| 3 | The protected set cannot be overridden | `Protection.isProtected` is checked first and returns before any rule; allow lists, tiers and wake windows for protected apps are ignored with a warning | `protectedSetIsNotOverridable`, `protectedAppsRefusedEvenOnRequest` |
| 4 | Whole trees, all or nothing | If any live process of a tree refuses SIGSTOP, everything already stopped is resumed and removed from the journal | `partialTreeFailureRollsBack`, `freezeAndThawWholeTreeWithJournal`, `freezeFailureRollsBack` |
| 5 | Bounded freeze time and size | Max 240 min per freeze (config range 1-1440, cannot be unbounded); max 8 apps and 50% of RAM frozen at once | `maxFrozenDurationThaws`, `budgetsBoundFrozenCountAndSize`, config range tests |
| 6 | No root, no SIP changes, no network, no telemetry | Per-user LaunchAgent without `UserName`; the daemon refuses to run as root; no networking or privilege APIs in product code; empty entitlements | `productCodeHasNoNetworkingOrPrivilegeEscalation`, `entitlementsGrantNothingDangerous`, `launchAgentIsPerUserAndNotRoot` |
| 7 | Everything is explainable | Every action carries reason codes and is logged to `actions.jsonl`; `iclean explain <app>` prints the current checks and recent actions | engine tests assert reason codes; `ipcRoundTrip` |
| 8 | Tests only signal their own processes | Tests and benchmarks signal only `ic-hog` children they spawned; `ic-hog` exits when its parent dies; `SpawnedHog.kill` refuses PID 0 | the whole suite runs on a live machine with the maintainer's apps open |

## What "protected" covers

Never frozen, deprioritised or asked to quit: anything under `/System` or `/usr`,
iClean itself, its parent and its children, Finder, Dock, SystemUIServer,
loginwindow, WindowServer, Spotlight, Control Center, Notification Center, security
agents, input methods, accessibility tools, terminals, AI coding-agent hosts,
password managers, backup and sync clients, and VPN clients. Menu-bar and background
apps are never frozen either, because only regular (Dock) apps are candidates. The
list is in [`Protection.swift`](../Sources/ICCore/Protection.swift). Additions are
welcome by pull request.

## Other guards

- Only apps with no on-screen window are frozen (a frozen window would still be drawn
  but could not respond).
- Audio playback or recording, power assertions (video, calls, downloads, builds),
  busy child processes, active network connections, dev servers with clients, recent
  writes and lock files all block a freeze. An app whose sockets and files were not
  inspected is never frozen.
- Messaging, mail, calendar and media apps are Tier S by default (frozen apps miss
  notifications and timers). They can be opted in, optionally with a wake window that
  thaws them for N seconds every M minutes.
- Docker, VMs, emulators and databases are Tier B: never frozen unless you opt in.
- Observe mode is the default and signals nothing.
- Focus Safe Mode pauses all automatic action during calls, screen sharing,
  mirroring and fullscreen use.
- Regret budget: too many freezes that the user undid by coming straight back make
  iClean act only on critical pressure for 24 hours.
- Quarantine: an app that crashes or hangs after a thaw is never frozen again until
  released.

## Red-team results

| Attack | Result | Test |
|---|---|---|
| `kill -9` the daemon mid-freeze | watchdog thawed the victim within the 5 s window | `watchdogThawsAfterDaemonIsKilled` |
| Kill daemon and watchdog | next daemon start, `iclean thaw --all`, or the menu's Resume all thaws from the journal | `daemonStartRecoversJournal`, `cliThawAllWorksWithoutDaemon` |
| Sleep/wake and unlock during a freeze | everything thawed | `wakeAndShutdownThawEverything`, `eventsThawEverything` |
| Cmd+Tab storm (200 alternating activations) | nothing left stopped, journal empty | `rapidActivationStorm` |
| App launches new helpers while frozen | helpers join the freeze | `newProcessesJoinAFrozenTree` |
| PID reuse | identity mismatch, no signal | `pidReuseGuardNeverSignalsAnotherProcess` |
| Journal corruption | moved aside; stopped app-bundle processes resumed; terminal job-control stops untouched | `corruptJournalFallback` |
| Two daemons | second one refuses to start (flock) | `secondInstanceIsRefused`, `watchdogThawsAfterDaemonIsKilled` |
| Disk full / journal unwritable | nothing is signalled | `journalWriteFailureMeansNoFreeze` |
| Invalid config while running | previous config kept, error shown | `invalidConfigKeepsPreviousOne` |
| Frozen app holds a lock another app waits for | prevented by Write Guard for lock files and recent writes; advisory `flock` locks are **not** detectable (documented limit) | `recentWriteAndLockFile` |
| Permissions revoked mid-run | Accessibility loss only disables the responsiveness probe (returns "unknown") | not automated |
| Forecast false-alarm storm | forecast actions switch themselves off | `falseAlarmStormDisarms` |
| Regret budget flapping | conservative for a fixed 24 h, no on/off flapping | `dailyBudgetTurnsConservativeFor24h` |
| Oversized or corrupt trace files | bad lines skipped, record count bounded | `corruptInputIsSkipped` |
| Habit table poisoning by one unusual day | capped at 20 transitions per pair per day | `dailyCapLimitsPoisoning` |
| Guard bypass through helper processes | guards inspect every process of the tree | `daemonInspectsBeforeFreezing` |
| Quarantine release race | quarantine is set once per app; release is idempotent | `unhealthyThawQuarantines` |
