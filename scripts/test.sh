#!/bin/sh
# Builds and runs the test suite.
# The Swift Testing macro plugin in some Command Line Tools releases fails at random
# ("plugin for module 'TestingMacros' not found"); the build is retried a few times.
set -eu
cd "$(dirname "$0")/.."
tries=0
until swift build --build-tests -j 2 >/tmp/iclean-build.$$ 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ] || ! grep -q "TestingMacros" /tmp/iclean-build.$$; then
        cat /tmp/iclean-build.$$
        rm -f /tmp/iclean-build.$$
        exit 1
    fi
done
rm -f /tmp/iclean-build.$$
exec swift test --skip-build "$@"
