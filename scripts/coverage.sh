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
bin=$(find .build/debug -name '*PackageTests.xctest' -maxdepth 1 | head -1)
[ -f "$bin/Contents/MacOS/$(basename "$bin" .xctest)" ] && bin="$bin/Contents/MacOS/$(basename "$bin" .xctest)"
xcrun llvm-cov report "$bin" -instr-profile .build/debug/codecov/default.profdata \
    $(find Sources/ICCore -name '*.swift' | sort) | tail -n +1
