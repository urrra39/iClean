#!/bin/sh
# Lab setup for docs/VALIDATION.md: copies release builds of the lab tools to
# .work/lab/bin and creates ".work/lab/iClear Lab.app" once. The app is never rebuilt
# when it exists, because an ad-hoc signature change would invalidate the Accessibility
# permission given to it. Run phases with:
#   open -n ".work/lab/iClear Lab.app" --args validate <phase>
set -eu
cd "$(dirname "$0")/.."
swift build -c release
lab=.work/lab
mkdir -p "$lab/bin" "$lab/results"
# rm first: a running copy keeps its old file instead of being overwritten in place.
for t in ic-lab icleard iclear ic-hog ic-ui-probe ic-call-sim; do rm -f "$lab/bin/$t"; cp ".build/release/$t" "$lab/bin/$t"; done
app="$lab/iClear Lab.app"
if [ ! -d "$app" ]; then
    mkdir -p "$app/Contents/MacOS"
    swiftc -O scripts/lab-launcher.swift -o "$app/Contents/MacOS/iClear Lab"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.urrra39.iclear.lab</string>
<key>CFBundleName</key><string>iClear Lab</string>
<key>CFBundleExecutable</key><string>iClear Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>iClear Lab runs its own call simulator (ic-call-sim) to test Call Mode. Nothing is recorded or stored.</string>
</dict></plist>
PLIST
    codesign --force -s - "$app"
fi
echo "lab ready: $app"
