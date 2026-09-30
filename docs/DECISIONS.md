# Decisions

One line each: what was decided and why. Newest at the bottom.

1. **Freeze with `SIGSTOP`/`SIGCONT`, not Mach suspend.** Signals work for same-user processes without root; `task_for_pid` fails even on an own child (FEASIBILITY §1, §2).
2. **No forced reclaim.** `MADV_PAGEOUT`, `VM_BEHAVIOR_PAGEOUT` and `memorystatus_control` all fail unprivileged; the kernel compressor does the reclaim once an app stops touching memory (§3, §4).
3. **No privileged helper.** No tested mechanism needs one; a root component would add risk for no measured gain.
4. **Deprioritise with `PRIO_DARWIN_BG`.** Works cross-process for same-user processes (§3); read back via thread priority, not `getpriority`.
5. **Pressure polling is primary, `DispatchSource` is secondary.** The dispatch source delivered nothing during a 33 s warning period in a small process (§7).
6. **Measure relief as resident size plus system compressor/swap, never `phys_footprint` alone.** Footprint counts compressed pages and did not move when a frozen app was compressed (§4).
7. **Only freeze apps with no on-screen windows.** A frozen app's window stays drawn but dead (§1).
8. **Predictive thaw ships off.** Not measurable without Input Monitoring/Accessibility; the activation notification already arrives for frozen apps and thaw costs ~0.1 ms (§6, §8).
9. **Not a Mac App Store app.** App Sandbox returns `EPERM` for `kill()` on other processes (§9).
10. **Swift Testing instead of XCTest.** The Command Line Tools on the build machine ship Swift Testing but not XCTest; Swift Testing also runs on CI's Xcode images.
11. **Only regular (Dock) apps are frozen.** Menu-bar and background agents are often infrastructure (VPN, sync, input); leaving them alone is the safe default.
12. **Unknown regular apps are Tier A.** Every safety check still applies; a long hand-made list of "known safe" apps would go stale.
13. **Safari is Tier S by default.** Its web content runs in launchd-owned XPC services that are not in its process tree, so a freeze would be partial.
14. **Observe mode stays on until the user promotes it.** No silent switch to Active after 24 h; iClean suggests promotion with the numbers it collected.
15. **Observe mode tracks "virtual" freezes.** Would-be freezes are recorded and closed exactly like real ones, so regret and relief estimates exist before anything is ever signalled.
16. **Relief estimate is 60% of resident memory until measured.** The frozen hog in FEASIBILITY §4 lost 98% of its resident memory, but that data compressed well; realized relief replaces the estimate once known.
17. **Config is JSON merged onto defaults; unknown keys are errors.** Stdlib only, and a typo never silently does nothing.
18. **Golden traces are synthetic and deterministic.** Real traces would contain the maintainer's app list; the generator lives in the tests.
19. **The macOS 13 floor applies to every target.** `MenuBarExtra` needs 13, a single floor keeps one package, and macOS 12 could not be tested here.
