# Naming

Checked 2026-09-30.

The product is called **iClean**. Other things with similar names already exist:

| Name | What it is | Where |
|---|---|---|
| iClean (Mac App Store, id598606972) | Paid menu-bar cleaner that scans caches, downloads, logs and trash | [Mac App Store](https://apps.apple.com/ua/app/iclean/id598606972?mt=12) |
| iClean (App Store, id1458052560) | Digital run sheet for cleaning staff in healthcare and facilities | [App Store](https://apps.apple.com/us/app/iclean/id1458052560) |
| iClean: Smart Storage Cleaner | iPhone storage cleaner | [App Store](https://apps.apple.com/us/app/iclean-smart-storage-cleaner/id1661731615) |
| iClean - Phone Storage Cleaner | iPhone storage cleaner | [App Store](https://apps.apple.com/us/app/iclean-phone-storage-cleaner/id6448978567) |
| iCleaner-AI Storage Cleaner | Storage cleaner | [App Store](https://apps.apple.com/us/app/icleaner-ai-storage-cleaner/id6756098730) |
| iCleaner / iCleaner Pro | Jailbroken-iOS cleaner (localization repo and third-party scripts on GitHub) | GitHub search "ICleaner" |

Not found in these checks: a GitHub project named "ICleaner" that is a macOS disk
cleaner CLI, and anything called "iCleanMemory". Neither search proves they do not
exist.

This project is unrelated to all of the above. It is not a cache or disk cleaner,
and it never deletes files.

Choices made because of the collisions:

- **Bundle identifier:** `io.github.urrra39.iclean` (the maintainer's GitHub namespace).
- **LaunchAgent label:** `io.github.urrra39.iclean`.
- **Homebrew:** on 2026-09-30, neither `Formula/i/iclean.rb` in homebrew-core nor
  `Casks/i/iclean.rb` in homebrew-cask existed (GitHub API returned 404). Homebrew
  packages will use `iclean`. If the name is taken by the time of a submission, the
  package identifier becomes `iclean-mac`.
  The product name stays iClean.
- The README says the project is not affiliated with Apple Inc. and is unrelated to
  cleaners with similar names.
