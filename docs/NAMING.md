# Naming

The project was called **iClean** up to version 0.1.0 and is now **iClear**. The rename
moves it away from the many "iClean" storage and cache cleaners (it never cleaned
files). The old checks are kept at the end.

## iClear (checked 2026-10-01)

| Name | What it is | Where |
|---|---|---|
| iClear (App Store, id6466145717) | Camera-viewing app for iPhone/iPad (Photo & Video category); iPad apps can run on Apple Silicon Macs | [App Store](https://apps.apple.com/us/app/iclear/id6466145717) |
| iClear Selangor | Regional app (Malaysia App Store) | [App Store](https://apps.apple.com/my/app/iclear-selangor/id1600857419) |
| iClearIt | Self-help app for iPhone/iPad | [App Store](https://apps.apple.com/us/app/iclearit/id934761208) |
| iBeesoft iCleaner | Paid Mac disk/junk cleaner | [ibeesoft.com](https://www.ibeesoft.com/mac-cleaner/) |
| michaelye/iClear | Android ad-blocking project on GitHub | GitHub search "iclear" |
| "iClear Celeb HD Studio" | Not found by web search on 2026-10-01 | |

This project is unrelated to all of them. It is not a cleaner and never deletes
files. Not affiliated with Apple Inc.

Choices:

- **Bundle identifier and LaunchAgent label:** `io.github.urrra39.iclear` (the
  maintainer's GitHub namespace). Separate instances get a suffix, for example
  `io.github.urrra39.iclear.soak`.
- **Commands:** `iclear` (CLI) and `icleard` (daemon). The internal module prefix `IC`
  and the test tool `ic-hog` are unchanged.
- **Homebrew:** on 2026-10-01, `Formula/i/iclear.rb` (homebrew-core),
  `Casks/i/iclear.rb` (homebrew-cask) and `Formula/i/iclear-mac.rb` did not exist (GitHub
  API returned 404). Packages use `iclear`; if that is taken at submission time, the
  package identifier becomes `iclear-mac`. The product name stays iClear.

## Earlier names checked for iClean (2026-09-30)

iClean (Mac App Store id598606972, a paid cache/download cleaner), iClean (id1458052560,
a cleaning-staff run sheet), iClean: Smart Storage Cleaner, iClean - Phone Storage
Cleaner, iCleaner-AI Storage Cleaner, and iCleaner / iCleaner Pro (jailbroken iOS).
