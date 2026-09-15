#!/bin/sh
# Builds the native switcher binary with Habu and installs it to ~/.local/bin.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
HABU=${HABU:-$HOME/Work/habu}
OUT="$HERE/build/switcher"
mkdir -p "$HERE/build"
cd "$HABU"
bin/hb --load tools/hb-build.f -- --repl "$HERE/src/switcher.f" -o "$OUT"
install -m 0755 "$OUT" "$HOME/.local/bin/switcher"
echo "installed $HOME/.local/bin/switcher"

# The shell watches for a replaced plugin folder; stage a copy and swap it in.
PLUGINS="$HOME/.config/omarchy/plugins"
STAGE="$PLUGINS/.joel.switcher.staging"
mkdir -p "$PLUGINS"
rm -rf "$STAGE"
cp -r "$HERE/plugin/joel.switcher" "$STAGE"
rm -rf "$PLUGINS/joel.switcher"
mv "$STAGE" "$PLUGINS/joel.switcher"
echo "installed $PLUGINS/joel.switcher"
