#!/usr/bin/env bash
# Build InterviewHelperMac as a real .app bundle (bundle ID + Screen Recording name).
# Usage: assemble-mac-app.sh <debug|release>
set -euo pipefail

CONFIG="${1:?usage: $0 <debug|release>}"
case "$CONFIG" in
  debug | release) ;;
  *)
    echo "Invalid configuration: $CONFIG (use debug or release)" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macos-native"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="InterviewHelperMac"
APP_DIR="$DIST_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "Building Swift ($CONFIG)…"
swift build --package-path "$SWIFT_DIR" -c "$CONFIG"

BIN_DIR="$(swift build --package-path "$SWIFT_DIR" -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "Expected executable not found: $BIN" >&2
  exit 1
fi

echo "Assembling $APP_DIR …"
mkdir -p "$DIST_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/.env" "$RESOURCES_DIR/.env" 2>/dev/null || true
bash "$ROOT_DIR/scripts/build-mac-icon.sh" "$RESOURCES_DIR/AppIcon.icns"

export ASSEMBLE_ROOT_DIR="$ROOT_DIR"
export ASSEMBLE_INFO_PLIST="$APP_DIR/Contents/Info.plist"
python3 <<'PY'
import os
import plistlib
from pathlib import Path

root = Path(os.environ["ASSEMBLE_ROOT_DIR"]).resolve()
out = Path(os.environ["ASSEMBLE_INFO_PLIST"])

data = {
    "CFBundleName": "InterviewHelperMac",
    "CFBundleDisplayName": "InterviewHelperMac",
    "CFBundleIconFile": "AppIcon",
    "CFBundleIdentifier": "com.interviewhelper.mac",
    "CFBundleVersion": "1",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleExecutable": "InterviewHelperMac",
    "CFBundlePackageType": "APPL",
    "LSUIElement": True,
    "NSPrincipalClass": "NSApplication",
    "NSScreenCaptureUsageDescription": (
        "Interview Helper captures the display under the cursor to send a screenshot "
        "to your local analysis server."
    ),
    "LSEnvironment": {
        "IH_PROJECT_ROOT": str(root),
    },
}
out.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
PY

echo "Done: $APP_DIR"
