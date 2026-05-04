#!/usr/bin/env bash
# Build AppIcon.icns from macos-native/Resources/AppIcon-1024.png (square, ≥1024).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macos-native"
MASTER="$SWIFT_DIR/Resources/AppIcon-1024.png"
OUT_ICNS="${1:-$SWIFT_DIR/Resources/AppIcon.icns}"

if [[ ! -f "$MASTER" ]]; then
  echo "Missing icon master: $MASTER" >&2
  exit 1
fi

# iconutil requires the directory name to end with ".iconset" (not just any temp folder).
ICONSET="${TMPDIR:-/tmp}/InterviewHelperMac.AppIcon.$$.iconset"
rm -rf "$ICONSET"
mkdir "$ICONSET"
cleanup() { rm -rf "$ICONSET"; }
trap cleanup EXIT

mk() {
  local name="$1" size="$2"
  sips --resampleHeightWidth "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
}

mk icon_16x16.png 16
mk icon_16x16@2x.png 32
mk icon_32x32.png 32
mk icon_32x32@2x.png 64
mk icon_128x128.png 128
mk icon_128x128@2x.png 256
mk icon_256x256.png 256
mk icon_256x256@2x.png 512
mk icon_512x512.png 512
mk icon_512x512@2x.png 1024

mkdir -p "$(dirname "$OUT_ICNS")"
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "Wrote $OUT_ICNS"
