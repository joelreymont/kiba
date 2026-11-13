#!/bin/sh
# Runs the kiba tests with the installed Habu, the one `hb` on PATH resolves
# to, inside a scratch HOME with nothing else inherited: CLAUDE_CONFIG_DIR or
# CODEX_HOME would point the suite at real credentials.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
HB=$(command -v hb) || { echo 'test.sh: hb is not on PATH' >&2; exit 127; }
HABU=$(dirname "$(dirname "$(readlink -f "$HB")")")
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
cd "$HABU"
env -i HOME="$SCRATCH" XDG_DATA_HOME="$SCRATCH/data" PATH="$SCRATCH/bin" KIBA_TEST_LOG="$SCRATCH/collector.log" \
  bin/hb --load "$HERE/test/sw-unit-test.f" </dev/null
