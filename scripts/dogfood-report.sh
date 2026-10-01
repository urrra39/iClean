#!/bin/sh
# Prints a sanitized summary of a dogfooding trial for docs/COMPATIBILITY.md.
# Numbers only: no hostname, user name, paths, or app names.
# Usage: scripts/dogfood-report.sh [days]   (default 7)
set -eu
DAYS="${1:-7}"
ICLEAR="${ICLEAR:-iclear}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$ICLEAR" stats --days "$DAYS" --json > "$TMP/stats.json"
"$ICLEAR" status --json > "$TMP/status.json"

get() { plutil -extract "$2" raw -o - "$TMP/$1" 2>/dev/null || echo "n/a"; }
minutes() { plutil -extract "$1" raw -o - "$TMP/stats.json" 2>/dev/null || echo 0; }

{
    echo "### iClear dogfooding summary ($DAYS days)"
    echo
    "$ICLEAR" doctor --report | sed '1d'
    echo "| Mode now | $(get status.json mode) |"
    echo "| Minutes in warning (Observe / Active) | $(minutes observeMinutes.warning) / $(minutes activeMinutes.warning) |"
    echo "| Minutes in critical (Observe / Active) | $(minutes observeMinutes.critical) / $(minutes activeMinutes.critical) |"
    echo "| Would-freeze (Observe) / freezes (Active) / thaws | $(get stats.json wouldFreeze) / $(get stats.json freezes) / $(get stats.json thaws) |"
    echo "| Regretted / closed freezes | $(get stats.json regretted) / $(get stats.json closedFreezes) |"
    echo "| Thaw latency p50 / p95 (ms) | $(get stats.json thawP50Ms) / $(get stats.json thawP95Ms) |"
    echo "| Average reclaimed per freeze (MB) | $(get stats.json reliefAvgMB) |"
    echo "| Forecast hits / false alarms / missed | $(get stats.json forecastHits) / $(get stats.json forecastFalseAlarms) / $(get stats.json forecastMissed) |"
    q=$(plutil -extract quarantined json -o - "$TMP/stats.json" 2>/dev/null || echo "[]")
    echo "| Quarantined apps (count) | $([ "$q" = "[]" ] && echo 0 || echo "$q" | awk -F'","' '{print NF}') |"
} | sed -e "s|$HOME|~|g" -e "s|$(whoami)|<user>|g" -e "s|$(hostname -s)|<host>|g"
