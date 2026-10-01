#!/bin/sh
# Starts the 7-day soak (docs/RELEASE_CRITERIA.md, stage 2) as two per-user LaunchAgents:
#   soak-lab      an Active, scope-locked lab instance that only acts on its own hidden
#                 ic-ui-probe fixture apps (supervised by `ic-lab soak` in iClear Lab.app)
#   soak-observe  an Observe-only instance on the real apps; it can never pause anything
# Reports go to .work/soak/. Check with scripts/soak-status.sh, stop with scripts/soak-stop.sh.
# Run scripts/lab-app.sh first.
set -eu
cd "$(dirname "$0")/.."
root=$PWD
lab="$root/.work/lab"
soak="$root/.work/soak"
agents="$HOME/Library/LaunchAgents"
uid=$(id -u)
[ -x "$lab/bin/ic-lab" ] && [ -d "$lab/iClear Lab.app" ] || { echo "Run scripts/lab-app.sh first." >&2; exit 1; }
mkdir -p "$soak" "$agents"
registry="$soak/lab-home/Library/Application Support/iClear-soak/lab-registry.json"

cat > "$agents/io.github.urrra39.iclear.soak-lab.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>io.github.urrra39.iclear.soak-lab</string>
<key>ProgramArguments</key><array><string>$lab/iClear Lab.app/Contents/MacOS/iClear Lab</string><string>soak</string></array>
<key>EnvironmentVariables</key><dict><key>ICLEAR_SOAK_DIR</key><string>$soak</string></dict>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>30</integer>
<key>StandardErrorPath</key><string>$soak/lab-agent.log</string>
</dict></plist>
PLIST

cat > "$agents/io.github.urrra39.iclear.soak-observe.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>io.github.urrra39.iclear.soak-observe</string>
<key>ProgramArguments</key><array><string>$lab/bin/icleard</string></array>
<key>EnvironmentVariables</key><dict>
<key>ICLEAR_INSTANCE</key><string>observe</string>
<key>ICLEAR_OBSERVE_ONLY</key><string>1</string>
<key>ICLEAR_IGNORE_REGISTRY</key><string>$registry</string>
</dict>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Adaptive</string>
<key>StandardErrorPath</key><string>$soak/observe-agent.log</string>
</dict></plist>
PLIST

for a in soak-lab soak-observe; do
    launchctl bootout "gui/$uid/io.github.urrra39.iclear.$a" 2>/dev/null || true
    launchctl bootstrap "gui/$uid" "$agents/io.github.urrra39.iclear.$a.plist"
done
[ -f "$soak/started" ] || date -u +%Y-%m-%dT%H:%M:%SZ > "$soak/started"
echo "Soak running since $(cat "$soak/started"). Status: scripts/soak-status.sh"
