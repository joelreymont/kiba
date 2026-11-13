#!/bin/sh
# Builds the native kiba binary with the installed Habu, the one `hb` on PATH
# resolves to, and installs it to ~/.local/bin.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
HB=$(command -v hb) || { echo 'build.sh: hb is not on PATH' >&2; exit 127; }
HABU=$(dirname "$(dirname "$(readlink -f "$HB")")")
OUT="$HERE/build/kiba"
mkdir -p "$HERE/build"
cd "$HABU"
bin/hb --load tools/hb-build.f -- --repl "$HERE/src/kiba.f" -o "$OUT"
install -m 0755 "$OUT" "$HOME/.local/bin/kiba"
echo "installed $HOME/.local/bin/kiba"

# The shell watches for a replaced plugin folder; stage a copy and swap it in.
PLUGINS="$HOME/.config/omarchy/plugins"
STAGE="$PLUGINS/.kiba.staging"
mkdir -p "$PLUGINS"
rm -rf "$STAGE"
cp -r "$HERE/plugin/kiba" "$STAGE"
rm -rf "$PLUGINS/kiba"
mv "$STAGE" "$PLUGINS/kiba"
echo "installed $PLUGINS/kiba"
