#!/bin/sh
# Prints the soak's progress against W1-W6 and the latest daily report.
set -eu
cd "$(dirname "$0")/.."
soak="$PWD/.work/soak"
uid=$(id -u)
[ -f "$soak/started" ] || { echo "No soak has been started."; exit 1; }
for a in soak-lab soak-observe; do
    if launchctl print "gui/$uid/io.github.urrra39.iclear.$a" >/dev/null 2>&1; then
        pid=$(launchctl print "gui/$uid/io.github.urrra39.iclear.$a" | awk '/^\tpid =/ {print $3}')
        echo "$a: loaded, pid ${pid:-none}"
    else
        echo "$a: not loaded"
    fi
done
ICLEAR_SOAK_DIR="$soak" .work/lab/bin/ic-lab soak-status
