# Trace format (version 1)

Traces are JSON Lines files in `~/Library/Application Support/iClean/traces/`, one
file per day (`YYYY-MM-DD.jsonl`). They hold bundle identifiers, app display names,
process IDs, numbers and timestamps. They never hold window titles, file paths, URLs
or content. Retention: 7 days and 20 MB total by default
(`trace.retentionDays`, `trace.maxMB`); longer retention is opt-in. Turn traces off
with `"trace": {"enabled": false}`.

Every line is one object:

| Key | Type | Meaning |
|---|---|---|
| `v` | int | format version, always 1 |
| `k` | string | `tick`, `activate` or `action` |
| `t` | number | seconds since 1970 |
| `tick` | object | for `tick`: the engine input (below) |
| `app`, `name`, `wd`, `h` | | for `activate`: bundle ID, display name, weekday (1 = Sunday), hour |
| `action` | object | for `action`: what iClean did or would do (`kind`, `appID`, `name`, `processes`, `reasons`, `dryRun`, `reliefEstimateMB`, `delaySeconds`, `message`) |

`tick` holds `sample` (pressure level 1/2/4, `availablePercent`, `physicalMB`,
`freeMB`, `compressedMB`, `swapUsedMB`, cumulative `swapOuts`/`swapIns`, `thermal`
0-3, `onBattery`, `batteryPercent`, `lowPowerMode`, `freeDiskGB`), `apps` (all regular
apps plus the 20 largest other processes: `id`, `name`, `processes` as
`{pid, startTime}`, `residentMB`, `footprintMB`, `cpuPercent`, `isFrontmost`,
`hasVisibleWindow`, `isHidden`, `isRegularApp`, `isElectron`, `origin`,
`partialTree`, `isDaemonLineage`, `signals`), `session` (camera, microphone, screen
sharing, mirroring, fullscreen, lock) and `weekday`, `hour`, `events`.

Readers skip lines that are not valid JSON, are longer than 1 MB, or have `v` ≠ 1,
and count them as skipped.

`iclean trace export --anonymize` replaces bundle IDs and names with salted hashes
(`app-…`, a new salt per export), zeroes process IDs, and drops action messages, so
a trace can be attached to a bug report.

`iclean simulate [--config FILE] [--since 7d]` replays `tick` and `activate` records
through the engine in Active mode. Recorded `action` lines are ignored (they describe
what happened, not inputs).
