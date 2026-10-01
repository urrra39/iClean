# Compatibility

iClean adapts to any MacBook that runs macOS 13 or later: it reads the RAM size, disk
type, battery and macOS version at start and picks thresholds from them (see
[ARCHITECTURE.md](ARCHITECTURE.md), "Profiles"). That is not the same as "tested on
every MacBook". This table lists only what was actually tested.

| Model identifier | Chip | RAM | macOS | Disk | SIGSTOP freeze | BG priority | Per-app audio | Tested by | Date |
|---|---|---|---|---|---|---|---|---|---|
| Mac15,6 | Apple M3 Pro | 18 GB | 27.0.1 | SSD | yes | yes | yes | maintainer (full test suite, benchmarks, install/uninstall, release artifacts) | 2026-10-01 |
| GitHub runner `macos-15` | Apple Silicon | runner | 15.7.9 | not checked | yes (tests) | yes (tests) | n/a | CI: build + 131 tests | 2026-10-01 |
| GitHub runner `macos-15-intel` | Intel x86_64 | runner | 15.7.9 | not checked | yes (tests) | yes (tests) | n/a | CI: build + 131 tests | 2026-10-01 |
| GitHub runner `macos-26` | Apple Silicon | runner | 26.6.2 | not checked | yes (tests) | yes (tests) | n/a | CI: build + 131 tests | 2026-10-01 |

CI rows mean the automated test suite passed there, including real SIGSTOP/SIGCONT
against spawned test processes. They are not real-use reports.

Untested so far: real use on Intel Macs (only the CI test suite has run on Intel), Macs
with 8 GB or less, spinning or Fusion disks, macOS 13 and 14, and Rosetta.

## Add your Mac

Run:

```sh
iclean doctor --report
```

and paste the output into a new issue using the "Compatibility report" template.
The report contains the model identifier, chip architecture, RAM, macOS version, disk
type and which mechanisms work. It collects no hostname, user name, serial number,
hardware UUID or IP address. Read it before you paste it.
