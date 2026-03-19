#!/bin/bash
set -euo pipefail

CONFIG="${1:-ReleaseLocal}"
TARGET="${2:-}"

if [[ -z "$TARGET" ]]; then
  if [[ "$CONFIG" == "Debug" ]]; then
    TARGET="/Applications/Ghostty Debug.app"
  else
    TARGET="/Applications/Ghostty.app"
  fi
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/macos/build.nu"
APP_SOURCE="$ROOT_DIR/macos/build/$CONFIG/Ghostty.app"
TMP_TARGET="${TARGET}.tmp"

if [[ "$CONFIG" != "Debug" ]]; then
  echo "Refreshing GhosttyKit.xcframework (ReleaseFast)..."
  (
    cd "$ROOT_DIR"
    zig build -Doptimize=ReleaseFast -Demit-macos-app=false
  )
fi

echo "Building Ghostty ($CONFIG)..."
"$BUILD_SCRIPT" --scheme Ghostty --configuration "$CONFIG" --action build

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Build output not found: $APP_SOURCE" >&2
  exit 1
fi

echo "Installing to $TARGET..."
rm -rf "$TMP_TARGET"
mkdir -p "$(dirname "$TARGET")"
ditto "$APP_SOURCE" "$TMP_TARGET"
rm -rf "$TARGET"
mv "$TMP_TARGET" "$TARGET"

echo "Installed:"
echo "  $TARGET"
echo
echo "Bundle identifier:"
defaults read "$TARGET/Contents/Info" CFBundleIdentifier
