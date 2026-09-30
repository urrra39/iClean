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
