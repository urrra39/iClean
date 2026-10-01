#!/bin/sh
# Line coverage of ICCore from its unit tests (docs/RELEASE_CRITERIA.md C10: >= 90%).
set -eu
cd "$(dirname "$0")/.."
tries=0
until swift build --build-tests --enable-code-coverage -j 2 >/tmp/iclear-cov.$$ 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ] || ! grep -q "TestingMacros" /tmp/iclear-cov.$$; then cat /tmp/iclear-cov.$$; exit 1; fi
done
rm -f /tmp/iclear-cov.$$
swift test --skip-build --enable-code-coverage --filter ICCoreTests >/dev/null
# SwiftPM puts products in .build/debug or, with the newer build system, .build/out/Products/Debug.
bin=$(find .build -path '*ICCoreTests.xctest/Contents/MacOS/ICCoreTests' -type f | head -1)
prof=$(find .build -path '*codecov/default.profdata' -type f | head -1)
xcrun llvm-cov report "$bin" -instr-profile "$prof" $(find Sources/ICCore -name '*.swift' | sort)
