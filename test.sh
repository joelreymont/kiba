#!/bin/sh
# Runs the kiba tests inside a scratch HOME so real credentials are never touched.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
HABU=${HABU:-$HOME/Work/habu}
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
cd "$HABU"
env HOME="$SCRATCH" XDG_DATA_HOME="$SCRATCH/data" PATH="$SCRATCH/bin" KIBA_TEST_LOG="$SCRATCH/collector.log" \
  bin/hb --load "$HERE/test/sw-unit-test.f" </dev/null
