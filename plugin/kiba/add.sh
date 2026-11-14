#!/bin/sh
# The widget's add: kiba add runs in a terminal of its own, because the
# provider's login prompts there. script(1) gives it that terminal and keeps
# a copy of what it printed. The terminal runs in the foreground until its
# command ends, so once it closes, kiba's own lines are this script's output
# (its reasons on stderr) and kiba's exit status is this script's.
#   add.sh <claude|codex> [name]
set -u

# inside the terminal, given the run directory; the status file says kiba
# add ended
if [ "${1:-}" = --in ]; then
  run=$2
  shift 2
  KIBA_ADD_P=$1 KIBA_ADD_N=${2:-} SHELL=/bin/sh \
    script -qec 'exec kiba add "$KIBA_ADD_P" ${KIBA_ADD_N:+"$KIBA_ADD_N"}' "$run/log"
  rc=$?
  echo "$rc" > "$run/status"
  if [ "$rc" -ne 0 ]; then
    printf '\nPress Enter to close\n'
    read -r _
  fi
  exit "$rc"
fi

# the session log holds the login's output and whatever the terminal echoed
# of what was typed, so it stays in a private directory that goes when this
# script ends
run=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/kiba-add.XXXXXX") || exit 1
trap 'rm -rf "$run"' EXIT
# the terminal's own messages matter only when kiba add never ended in it
xdg-terminal-exec --title="Kiba: add $1" -- sh "$0" --in "$run" "$@" > /dev/null 2> "$run/terminal"
if [ ! -r "$run/status" ]; then
  echo "kiba: the login terminal closed before kiba add ended" >&2
  cat "$run/terminal" >&2
  exit 1
fi
# kiba's lines may follow whatever the login left on its last line, so they
# are matched wherever they start
tr -d '\r' < "$run/log" | grep -oE '(claude|codex): saved .*$'
tr -d '\r' < "$run/log" | grep -oE 'kiba: .*$' >&2
exit "$(cat "$run/status")"
