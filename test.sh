#!/bin/sh
# Runs the kiba tests with the installed Habu, the one `hb` on PATH resolves
# to, inside a scratch HOME with nothing else inherited: CLAUDE_CONFIG_DIR or
# CODEX_HOME would point the suite at real credentials. A second run in its
# own scratch HOME starts kiba with both set to paths under that HOME, the
# way a user's shell would, and checks that `add` hides them from the login.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
HB=$(command -v hb) || { echo 'test.sh: hb is not on PATH' >&2; exit 127; }
HABU=$(dirname "$(dirname "$(readlink -f "$HB")")")
SCRATCH=$(mktemp -d)
SCRATCH2=
trap 'rm -rf "$SCRATCH" ${SCRATCH2:+"$SCRATCH2"}' EXIT
SCRATCH2=$(mktemp -d)
cd "$HABU"
env -i HOME="$SCRATCH" XDG_DATA_HOME="$SCRATCH/data" PATH="$SCRATCH/bin" KIBA_TEST_LOG="$SCRATCH/collector.log" \
  bin/hb --load "$HERE/test/sw-unit-test.f" </dev/null
env -i HOME="$SCRATCH2" XDG_DATA_HOME="$SCRATCH2/data" PATH="$SCRATCH2/bin" KIBA_TEST_LOG="$SCRATCH2/collector.log" \
  CLAUDE_CONFIG_DIR="$SCRATCH2/real-home/.claude" CODEX_HOME="$SCRATCH2/real-home/.codex" \
  bin/hb --load "$HERE/test/sw-unit-test.f" </dev/null
