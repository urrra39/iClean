# Phase 0 feasibility

Before writing the product I tested each mechanism the design depends on.
The experiments live in [`spikes/`](../spikes) and can be re-run. Every
number below was measured on one machine:

- **Hardware:** Apple M3 Pro, 18 GB RAM, internal SSD
- **OS:** macOS 27.0.1
- **Date:** 2026-09-30
- **Context:** a normal user session, run from a terminal that had *not*
  been granted Screen Recording, Input Monitoring or Accessibility.

Safety rules for the experiments: they only signal `ic-hog` processes that
they spawned themselves, induced memory pressure is capped (50% of RAM, abort
at critical pressure or when swap grows by more than 1 GB), and all hogs are
killed on exit (signal handlers plus `atexit`).

## Decision table

| # | Mechanism | Verdict | Evidence (below) |
|---|-----------|---------|------------------|
| 1 | `SIGSTOP`/`SIGCONT` on same-user apps, no root | **Works** | §1 |
| 2 | Mach `task_for_pid` + `task_suspend` | **Not viable** (dropped) | §2 |
| 2b | Private `pid_suspend` | **Not viable** without root | §2 |
| 3 | Forcing another process's pages out (`MADV_PAGEOUT`, `VM_BEHAVIOR_PAGEOUT`, `memorystatus_control`) | **Not viable** | §3 |
| 3b | `setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG)` cross-process | **Works** | §3 |
| 4 | `SIGSTOP` letting the kernel reclaim a frozen app's memory | **Works with caveat**: only under pressure, and only for apps that would otherwise keep touching memory | §4 |
| 5 | Thaw latency | **Works**: sub-millisecond to schedule; page fault-in dominates | §5 |
| 6 | Frontmost detection via `NSWorkspace.didActivateApplicationNotification` | **Works**, including for a frozen app | §6 |
| 6b | `CGWindowListCopyWindowInfo` without Screen Recording | **Works** for owner PID, layer, bounds, on-screen flag; no window titles | §6 |
| 7 | `DispatchSource` memory-pressure source as the only trigger | **Not reliable**; polling `kern.memorystatus_vm_pressure_level` is primary | §7 |
| 8 | Predictive thaw (event tap, Accessibility Dock hover) | **Not measured** (needs permissions); ships off, experimental | §8 |
| 9 | Signalling other processes from inside App Sandbox | **Blocked** (`EPERM`): no Mac App Store build | §9 |

**Shipping architecture chosen from this evidence:** freeze with
`SIGSTOP`/`SIGCONT` over the whole process tree, deprioritise with
`PRIO_DARWIN_BG`, and rely on the kernel's own compressor and swap for the
actual reclaim ("freeze + kernel-assisted reclaim"). There is no privileged
helper: no mechanism tested here needs one, and the ones that would need root
(Mach suspend, `memorystatus_control`) are not worth a root install.

## §1 Signal freeze of a GUI app

Spike: [`gui_spike.swift`](../spikes/gui_spike.swift), target an `ic-hog --gui`
app it launched itself.

- Before: `ps` state `S`, listed in `NSWorkspace.runningApplications`, 5 windows.
- 3 s after `SIGSTOP`: `ps` state `T`, still listed as running (not
  terminated), all windows still present and the main window still on
  screen. WindowServer keeps showing the last frame.
- After `SIGCONT`: state back to `R`/`S`, heartbeats resume.

Caveats that drive the design:

- A frozen app with a *visible* window looks alive but cannot redraw or take
  input, so iClean only freezes apps with no on-screen windows.
- A frozen process misses timers, notifications and network callbacks.
  Remote peers may time out its connections. This is why messaging, mail and
  calendar apps are never frozen by default, and why Connection Guard exists.
- No data is lost by `SIGSTOP` itself (memory is untouched), but a frozen
  process holding a file lock blocks anyone waiting on that lock. This is why
  Write Guard exists.

## §2 Mach suspend

Spike: [`mach_and_reclaim.c`](../spikes/mach_and_reclaim.c), run as uid 501.

```
task_for_pid(own forked child): kr=5 ((os/kern) failure)
task_name_for_pid: kr=0 ((os/kern) successful) (name ports cannot suspend or touch memory)
pid_suspend (private): rc=-1 errno=1 (Operation not permitted)
```

`task_for_pid` fails even for a child the process forked itself. Mach suspend
is dropped. I did not test it as root: a root requirement is out of scope
for the default install, and signals already work.

## §3 Forced reclaim and deprioritisation

Same spike:

```
memorystatus_control(GET_PRIORITY_LIST size probe): rc=-1 errno=1 (Operation not permitted)
memorystatus_control(SET_JETSAM_HIGH_WATER_MARK on child): rc=-1 errno=1 (Operation not permitted)
madvise(self, 256MB, MADV_PAGEOUT): rc=-1 errno=45 resident 257 -> 257 MB
mach_vm_behavior_set(self, VM_BEHAVIOR_PAGEOUT): kr=4 ((os/kern) invalid argument) resident now 257 MB
setpriority(PRIO_DARWIN_PROCESS, child, PRIO_DARWIN_BG): rc=0 errno=0
```

- `MADV_PAGEOUT` *is* defined in this SDK (`sys/mman.h`, value 10, commented
  "internal only"), but returns `ENOTSUP` even on the caller's own memory.
- `VM_BEHAVIOR_PAGEOUT` is commented "development only" and is rejected.
- Both would need a task port for another process anyway, and §2 shows
  that is unavailable.
- `memorystatus_control` needs root for every command tried.

So iClean cannot force another app's pages out. It can only stop the app
from touching its pages and let the kernel do the rest (§4).

`PRIO_DARWIN_BG` does work cross-process on a same-user process: the spawned
CPU-spinning hog's thread priority went from 31 to 4 (`ps -M`). Note that
`getpriority(PRIO_DARWIN_PROCESS, pid)` read back `0` afterwards, so the
read-back is not a reliable check. Verify with thread priorities instead.

## §4 Does freezing reduce memory use?

Spike: [`freeze_spike.swift`](../spikes/freeze_spike.swift). Two identical
victims each allocate 1024 MB of compressible data and re-touch every page
every 2 s, like a background app with timers. One is frozen, the other keeps
running. Then incompressible 512 MB hogs are added until the cap or an abort
condition.

```
baseline  frozen resident 1031 MB footprint 1026 | running resident 1031 footprint 1026 | compressor 1951 MB swap    0 MB free 133 MB level 1
+2048 MB  frozen resident   14 MB footprint 1026 | running resident 1030 footprint 1026 | compressor 3113 MB swap    0 MB free  80 MB level 1
+4096 MB  frozen resident   10 MB footprint 1026 | running resident 1030 footprint 1026 | compressor 5160 MB swap    0 MB free  77 MB level 1
+6144 MB  frozen resident   10 MB footprint 1026 | running resident 1030 footprint 1026 | compressor 8815 MB swap    0 MB free  90 MB level 2
induced 8192 MB of incompressible memory in 38.9 s, aborted: swap limit
hold 20s  frozen resident   10 MB footprint 1026 | running resident 1030 footprint 1026 | compressor 9307 MB swap 1503 MB free 146 MB level 2
```

Findings:

- Under pressure the frozen victim's resident memory fell from 1031 MB to
  14 MB within the first 2 GB of induced pressure. The running twin kept all
  1030 MB resident for the whole run.
- Without pressure (baseline row) freezing changes nothing. macOS only
  reclaims when it needs memory.
- `phys_footprint` did **not** change for either process. It counts
  compressed pages too. So iClean reports relief from resident size and
  system compressor/swap, never from footprint alone.
- The benefit comes from apps that keep touching memory while in the
  background. An app that is idle and never wakes up gets compressed anyway,
  frozen or not. iClean's value is limited to the first kind.
- The swap-limit abort fired late (swap reached 1.5 GB against a 1 GB limit),
  because swap kept growing after the last check. The benchmark harness
  checks more often and uses a lower cap.

## §5 Thaw latency

20 freeze/thaw cycles per size, no induced pressure. "First heartbeat" is when
the process runs again. "All pages touched" is the worst case where the app
immediately needs its whole working set.

| Hog size | SIGCONT → first heartbeat (p50 / p95) | SIGCONT → all pages touched (p50 / p95 / max) |
|---------:|-----------------|------------------|
| 64 MB | 0.13 / 0.16 ms | 0.25 / 0.31 / 0.34 ms |
| 512 MB | 0.03 / 0.04 ms | 0.39 / 1.58 / 5.71 ms |
| 2048 MB | 0.03 / 0.05 ms | 1.58 / 4.63 / 62.18 ms |

Under pressure (1024 MB victim whose pages had been compressed, from §4):
first heartbeat 0.04 ms, all 1024 MB touched after **191 ms**.

The signal itself is effectively free. The cost users can feel is faulting
compressed or swapped pages back in, and it grows with how much memory was
reclaimed. That is the trade-off Regret-aware decisions (S2) accounts for.

## §6 Frontmost detection and window information

`CGWindowListCopyWindowInfo` without Screen Recording returned, for the hog's
windows: `kCGWindowAlpha, kCGWindowBounds, kCGWindowIsOnscreen (on-screen
windows only), kCGWindowLayer, kCGWindowMemoryUsage, kCGWindowNumber,
kCGWindowOwnerName, kCGWindowOwnerPID, kCGWindowSharingState,
kCGWindowStoreType`. No `kCGWindowName`. That is enough for "does this app
have an on-screen window"; iClean never needs titles.

Activation timing (5 trials each):

```
app self-activation -> didActivate notification in observer: min 3.6 ms, median 4.1 ms, max 6.7 ms
`open -a` on running app -> didActivate: min 28.6 ms, median 36.5 ms, max 43.8 ms
`open -a` on FROZEN app -> didActivate: min 32.6 ms, median 40.0 ms, max 43.4 ms  (0 of 5 not delivered)
frozen app: didActivate -> SIGCONT -> first heartbeat: min 0.1 ms, median 0.1 ms, max 0.1 ms
```

- **The activation notification is delivered even when the app being
  activated is frozen.** This is the property the whole thaw path depends on.
- `open -a` numbers include starting the `open` process, so they overstate
  what a Dock click costs.
- `NSRunningApplication.activate()` called from a background command-line
  process was refused (cooperative activation), so these trials use
  self-activation and LaunchServices instead.
- The observer process creates `NSApplication.shared` before subscribing.
  An earlier attempt without it saw no notifications, but that run had
  another problem too, so I have not isolated the cause. The daemon creates
  `NSApplication.shared` (accessory policy) to be safe.

## §7 Memory-pressure events

During the §4 run the spike listened with both
`DispatchSource.makeMemoryPressureSource([.normal, .warning, .critical])` and a
100 ms poll of `kern.memorystatus_vm_pressure_level`:

```
sysctl:2 at +26109 ms
sysctl:1 at +59386 ms
```

The polled level went to 2 (warning) for about 33 s. **The dispatch source in
the same process delivered no event at all.** My working explanation is that
the kernel sends pressure notifications to selected processes (large ones
first), not to every subscriber. I have not verified this in the kernel
source. Either way, a small daemon cannot rely on the dispatch source. Polling
the sysctl is the primary trigger, and the dispatch source is kept as an
extra wake-up.

`memory_pressure -S -l warn` (simulated pressure) needs root
(`kern.memorypressure_manual_trigger failed : Operation not permitted`), so
tests use a fake pressure sensor and benchmarks induce real, bounded pressure.

## §8 Prediction inputs

- A listen-only `CGEventTap` for key events *was created* without Input
  Monitoring. Creation succeeding does not mean events are delivered, and I
  did not grant the permission to find out.
- `AXUIElementCopyElementAtPosition` without Accessibility returned
  `kAXErrorAPIDisabled` (-25211).

Not measured, so predictive thaw ships **off** and marked experimental. The
headroom it could win is bounded: the notification path already thaws in
about 0.1 ms after activation. Only the page fault-in time (up to 191 ms per
GB in §5) could be hidden, and only if the app faults its pages in before the
user looks at it.

## §9 App Sandbox

A probe binary signed with only `com.apple.security.app-sandbox` calling
`kill(pid, SIGSTOP)` on a spawned hog:

```
sandboxed kill(SIGSTOP) rc=-1 errno=1 Operation not permitted
```

The sandbox blocks signalling other processes, so iClean cannot be a Mac App
Store app. It is distributed as a signed (or ad-hoc signed) download and a
Homebrew formula.

## Side effect of running the spikes

The §4 pressure run left 1.5 GB in swap after the hogs exited. The swap
files shrink on their own over time. The benchmark harness uses a lower cap
for this reason.
