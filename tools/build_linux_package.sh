#!/usr/bin/env bash
# Stage the Linux release OUTSIDE the repo and tar it.
# Never stage into the project tree: Godot's import pass scans it and writes
# .import sidecars next to the assets, polluting the project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
BIN="$BUILD/Breakout.x86_64"
[ -f "$BIN" ] || { echo "missing $BIN — export first:" >&2
  echo "  godot --headless --path . --export-release \"Linux/X11\" $BIN" >&2
  exit 1; }
STAGE="$(mktemp -d /tmp/brick-press-package.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cp "$BIN" "$ROOT/icon.png" "$BUILD/breakout.desktop" "$BUILD/README-package.txt" "$STAGE/"
tar czf "$BUILD/Breakout-linux-x86_64.tar.gz" -C "$STAGE" Breakout.x86_64 icon.png breakout.desktop README-package.txt
echo "packaged -> $BUILD/Breakout-linux-x86_64.tar.gz"
tar tzf "$BUILD/Breakout-linux-x86_64.tar.gz"
