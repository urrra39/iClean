# Compatibility

iClean adapts to any MacBook that runs macOS 13 or later: it reads the RAM size, disk
type, battery and macOS version at start and picks thresholds from them (see
[ARCHITECTURE.md](ARCHITECTURE.md), "Profiles"). That is not the same as "tested on
every MacBook". This table lists only what was actually tested.

| Model identifier | Chip | RAM | macOS | Disk | SIGSTOP freeze | BG priority | Per-app audio | Tested by | Date |
|---|---|---|---|---|---|---|---|---|---|
| Mac15,6 | Apple M3 Pro | 18 GB | 27.0.1 | SSD | yes | yes | yes | maintainer (full test suite, benchmarks, install/uninstall) | 2026-09-30 |

Untested so far: Intel Macs (the universal binary builds, but has not run on Intel
hardware), Macs with 8 GB or less, spinning or Fusion disks, macOS 13-26, and
Rosetta.

## Add your Mac

Run:

```sh
iclean doctor --report
```

and paste the output into a new issue using the "Compatibility report" template.
The report contains the model identifier, chip architecture, RAM, macOS version, disk
type and which mechanisms work. It collects no hostname, user name, serial number,
hardware UUID or IP address. Read it before you paste it.
