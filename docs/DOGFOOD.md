# Dogfooding plan (7 days)

This is how the maintainer, or anyone, validates iClean on a real daily-use Mac. **No
results are claimed here yet.** Active mode on real apps has not been validated; this
plan is how it will be.

## Before you start

- Save your work. iClean never deletes anything, but a paused app does not run.
- Know the exits: Control-Option-Command-T (menu app running), "Resume all" in the
  menu, or `iclean thaw --all`. All of them work even if the daemon crashed.
- Optional: grant Accessibility to iClean so it can measure resume latency and detect
  apps that hang after resuming.

## Days 1-3: Observe

```sh
iclean install          # starts in Observe mode; nothing is signalled
iclean status
```

Use the Mac normally, including your heaviest days. Each evening:

```sh
iclean stats --days 1   # minutes in yellow/red, would-freeze count, would-be regret
iclean why              # when the Mac feels slow
```

Go to Active only if:

- the would-be regret rate is low (a few apps you came straight back to), and
- the would-freeze list contains only apps you are happy to see paused
  (`iclean explain <app>` for any surprises; `iclean config deny <app>` to exclude).

## Days 4-7: Active

```sh
iclean mode active
```

Watch for:

- an app you switch to that takes noticeably long to respond (note the app and time);
- missed notifications from an app you opted in;
- anything paused that should not have been (`iclean explain <app>`, then
  `iclean config deny <app>`);
- quarantined apps (`iclean quarantine`).

Go back at any time with `iclean mode observe`, which also resumes everything.

## Report

```sh
scripts/dogfood-report.sh 7
```

It prints numbers only (no hostname, user name, paths or app names). Read it, then
paste it into a compatibility issue or a pull request that adds a row to
[COMPATIBILITY.md](COMPATIBILITY.md). Include anything from the "watch for" list,
even if the report looks good.
