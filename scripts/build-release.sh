#!/bin/sh
# Builds universal (arm64 + x86_64) release binaries and assembles dist/iClean.app
# plus dist/iclean-<version>-macos.tar.gz.
#
# Signing: set SIGN_IDENTITY to a "Developer ID Application" identity to sign for
# distribution; otherwise the build is ad-hoc signed (see README, "First launch").
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^public let icleanVersion = "\(.*\)"/\1/p' Sources/ICSystem/Doctor.swift)
IDENTITY="${SIGN_IDENTITY:--}"
DIST=dist
APP="$DIST/iClean.app"

swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release"
[ -d "$BIN" ] || BIN=".build/out/Products/Release"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/iCleanMenu" "$APP/Contents/MacOS/iClean"
# Helpers/ keeps iclean apart from iClean on case-insensitive volumes.
cp "$BIN/icleand" "$BIN/iclean" "$APP/Contents/Helpers/"
cp -R "$BIN/iClean_iCleanMenu.bundle" "$APP/Contents/Resources/"
sed "s/@VERSION@/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"

sign() {
    codesign --force --timestamp=none --options runtime --entitlements packaging/iClean.entitlements -s "$IDENTITY" "$@"
}
sign "$APP/Contents/Helpers/icleand"
sign "$APP/Contents/Helpers/iclean"
sign "$APP"

# Command-line tarball: iclean, icleand and ic-hog (needed by `iclean bench`).
mkdir -p "$DIST/iclean-$VERSION"
cp "$BIN/iclean" "$BIN/icleand" "$BIN/ic-hog" "$DIST/iclean-$VERSION/"
for f in "$DIST/iclean-$VERSION"/*; do sign "$f"; done
tar -C "$DIST" -czf "$DIST/iclean-$VERSION-macos.tar.gz" "iclean-$VERSION"
(cd "$DIST" && ditto -c -k --keepParent iClean.app "iClean-$VERSION.zip")

lipo -info "$APP/Contents/Helpers/icleand"
echo "Built $APP and $DIST/iclean-$VERSION-macos.tar.gz (signed with: $IDENTITY)"
