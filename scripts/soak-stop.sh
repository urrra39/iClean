#!/bin/sh
# Stops both soak instances and, if installed, the read-only trace archiver
# (trace-archive). The lab supervisor resumes and closes its fixtures and stops its
# daemon (which resumes anything it paused); this script then checks that no soak
# process is left stopped. Reports, the Observe instance's data and the archive are kept.
set -eu
cd "$(dirname "$0")/.."
soak="$PWD/.work/soak"
uid=$(id -u)
for a in soak-lab soak-observe trace-archive; do
    launchctl bootout "gui/$uid/io.github.urrra39.iclear.$a" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/io.github.urrra39.iclear.$a.plist"
done
sleep 3
left=$(ps -axo stat=,command= | awk '$1 ~ /^T/ && /SoakProbe|ic-hog|iClear-soak/' | wc -l | tr -d ' ')
echo "Soak stopped. Soak processes left stopped: $left"
date -u +%Y-%m-%dT%H:%M:%SZ > "$soak/stopped"
[ "$left" = 0 ]
