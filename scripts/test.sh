#!/bin/sh
# Builds and runs the test suite.
# The Swift Testing macro plugin in some Command Line Tools releases fails at random
# ("plugin for module 'TestingMacros' not found"); the build is retried a few times.
set -eu
cd "$(dirname "$0")/.."
tries=0
# SCRATCH selects the build directory (the v1.1 work uses .build-v11).
S=${SCRATCH:-.build}
until swift build --build-tests -j 2 --scratch-path "$S" >/tmp/iclear-build.$$ 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ] || ! grep -q "TestingMacros" /tmp/iclear-build.$$; then
        cat /tmp/iclear-build.$$
        rm -f /tmp/iclear-build.$$
        exit 1
    fi
done
rm -f /tmp/iclear-build.$$
# Serial, as in CI: GUI suites hide and activate apps, which other GUI suites would see.
exec swift test --skip-build --no-parallel --scratch-path "$S" "$@"
