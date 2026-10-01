# Security policy

iClean sends signals to other processes, so safety bugs count as security bugs.
These include anything that could freeze a protected process, leave a process frozen,
signal the wrong process (PID reuse), or run with more privilege than the current
user.

## Reporting

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/urrra39/iClean/security/advisories/new)
for this repository. Do not open a public issue for them.

Include the macOS version, `iclean doctor --report` output, and steps to reproduce.
I aim to acknowledge reports within 7 days.

## Scope and design limits

- iClean runs as the logged-in user and refuses to run as root.
- It has no network code and no listening network sockets. The only IPC is a Unix
  domain socket in `~/Library/Application Support/iClean/` (mode 0700), and the
  daemon checks the peer's user ID.
- It never deletes files.
- Release builds are currently ad-hoc signed, not notarized. Build from source if
  you prefer to verify what you run.

## Supported versions

Only the latest release receives fixes.
