#!/usr/bin/env bash
# Downloads the Godot editor binary used by CI and the video recorder.
# Usage: tools/install_godot.sh [dest dir]   (prints the binary path on success)
set -euo pipefail
VERSION="${GODOT_VERSION:-4.4.1-stable}"
DEST="${1:-$HOME/godot}"
BIN="$DEST/godot"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  curl -fsSL -o "$DEST/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${VERSION}/Godot_v${VERSION}_linux.x86_64.zip"
  unzip -q -o "$DEST/godot.zip" -d "$DEST"
  mv "$DEST/Godot_v${VERSION}_linux.x86_64" "$BIN"
  rm "$DEST/godot.zip"
fi
"$BIN" --version >&2
echo "$BIN"
