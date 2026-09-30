# FAQ

**Does iClean delete anything?**
No. It pauses processes (`SIGSTOP`), resumes them (`SIGCONT`), lowers their priority,
and, only for apps you opt in, asks them to quit normally. It never deletes files,
caches or logs.

**Does macOS not do this already?**
Mostly, yes. macOS compresses and swaps memory well. iClean only helps when memory
pressure is actually high *and* background apps keep waking up and touching their
memory. That keeps macOS from reclaiming it (see
[BENCHMARKS.md](BENCHMARKS.md)). An app that is truly idle gets compressed by macOS
anyway. If your pressure graph is green, iClean does nothing.

**What happens to a paused app?**
It keeps all its memory contents and state, but it cannot run. Its timers,
notifications and network callbacks wait. Remote servers may drop its connections.
When you switch back, iClean resumes it immediately. The signal takes well under a
millisecond, and faulting reclaimed memory back in took 80 ms for 512 MB in the
benchmark.

**Why not just quit apps?**
Quitting loses state, and relaunching is slow. Pausing is reversible. iClean can ask
an app to quit (never force), but only for apps you list in `quitAllowed`, and only
at critical pressure.

**Will I miss messages?**
Messaging, mail, calendar and media apps are never paused by default. If you opt one
in, you can give it a wake window, for example "resume for 30 s every 10 min".

**Why does it start in Observe mode?**
So you can see what it *would* do, and its would-be regret rate, before it touches
anything. Switch with `iclean mode active` or the menu.

**Why no Mac App Store version?**
App Sandbox forbids signalling other processes (`kill` returns EPERM, measured in
[FEASIBILITY.md §9](FEASIBILITY.md)).

**Does it need root?**
No, and it refuses to run as root. It is a per-user LaunchAgent. No kernel extension,
no SIP changes.

**What permissions does it ask for?**
None are required. Accessibility is optional: it lets iClean check that a resumed app
responds, and measure thaw latency. Input Monitoring is only for the experimental
predictive thaw, which is off.

**Does it send data anywhere?**
No. iClean has no network code at all (a test enforces this). Everything it learns
stays in `~/Library/Application Support/iClean/`, in readable JSON you can delete.

**Something looks frozen. What do I do?**
Press Control-Option-Command-T, click "Resume all" in the menu, or run
`iclean thaw --all`. All three work even if the daemon has crashed.

**How do I see why an app was or was not paused?**
`iclean explain <app name>`.

**Is it the same as the iClean cleaner on the App Store?**
No, it is unrelated. See [NAMING.md](NAMING.md).
