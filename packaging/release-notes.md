iClear @VERSION@: pauses idle background apps on a Mac that is running out of memory and
resumes each one when you switch back to it. It starts in **Observe mode**, which only
records what it would do.

**Validated scope.** One Mac (Apple M3 Pro, 18 GB, macOS 27.0.1), in a lab with real
apps started by the lab (Chrome, VS Code, TextEdit, Preview) and simulators, never with
personal accounts. Results: `docs/VALIDATION.md`; criteria: `docs/RELEASE_CRITERIA.md`.
**Not validated:** real Slack, Spotify or any account; Intel Macs (CI tests only); macOS
13 and 14; 8 GB Macs; battery estimates (experimental, target mode off). A 7-day soak is
in progress; its results will be published separately.

## What is new since 0.1.0

Renamed from iClean (`iclear migrate` resumes and moves an old install safely). Workspace
Stash (`iclear stash`, `iclear pop`), `iclear selftest`, app classes with
`iclear compat <app>` (chat, mail, calendar and media apps are never paused by default),
`iclear before <app>`, Anti-Beachball forensics, battery estimates (experimental).
Call Mode and Anti-Beachball mitigation ship off: they did not meet their pre-registered
rules. "Known side effects" in the README lists what pausing does to chat apps, media
players and browsers. Full list: `CHANGELOG.md`.

## Downloads

- `iClear-@VERSION@.zip`: the menu-bar app; the command-line tools are inside
  `iClear.app/Contents/Helpers`.
- `iclear-@VERSION@-macos.tar.gz`: `iclear`, `icleard`, and iClear's own test tools
  `ic-hog`, `ic-ui-probe`, `ic-call-sim` (used by `iclear selftest` and `iclear bench`).

Universal binaries (arm64 and x86_64) for macOS 13 and later.

## First launch

These builds are ad-hoc signed and not notarized. App: right-click iClear.app, choose
Open, confirm. Command-line tools: unpack, run
`xattr -dr com.apple.quarantine iclear-@VERSION@`, then inside that folder
`./iclear selftest --quick` and `./iclear install`.

## Verify

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```
