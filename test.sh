#!/bin/sh
# Runs the kiba tests with the installed Habu, the one `hb` on PATH resolves
# to, inside a scratch HOME so real credentials are never touched.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
HB=$(command -v hb) || { echo 'test.sh: hb is not on PATH' >&2; exit 127; }
HABU=$(dirname "$(dirname "$(readlink -f "$HB")")")
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
cd "$HABU"
env HOME="$SCRATCH" XDG_DATA_HOME="$SCRATCH/data" PATH="$SCRATCH/bin" KIBA_TEST_LOG="$SCRATCH/collector.log" \
  bin/hb --load "$HERE/test/sw-unit-test.f" </dev/null
