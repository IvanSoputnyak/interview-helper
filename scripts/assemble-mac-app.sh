#!/usr/bin/env bash
# Build InterviewHelperMac as a sandboxed .app for Mac App Store / TestFlight.
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
bash "$ROOT_DIR/scripts/build-mac-icon.sh" "$RESOURCES_DIR/AppIcon.icns"
cp "$SWIFT_DIR/PrivacyInfo.xcprivacy" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"

export ASSEMBLE_INFO_PLIST="$APP_DIR/Contents/Info.plist"
python3 <<'PY'
import plistlib
from pathlib import Path

out = Path(__import__("os").environ["ASSEMBLE_INFO_PLIST"])
data = {
    "CFBundleName": "Interview Helper",
    "CFBundleDisplayName": "Interview Helper",
    "CFBundleIconFile": "AppIcon",
    "CFBundleIdentifier": "com.interviewhelper.mac",
    "CFBundleVersion": "1",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleExecutable": "InterviewHelperMac",
    "CFBundlePackageType": "APPL",
    "LSMinimumSystemVersion": "13.0",
    "LSUIElement": True,
    "NSPrincipalClass": "NSApplication",
    "NSScreenCaptureUsageDescription": (
        "Interview Helper captures the display under your cursor to analyze coding interview questions. "
        "Screenshots are sent to OpenAI using your API key."
    ),
    "ITSAppUsesNonExemptEncryption": False,
}
out.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
PY

ENTITLEMENTS="$SWIFT_DIR/InterviewHelperMac.entitlements"
if [[ -x "$(command -v codesign)" ]]; then
  echo "Signing with sandbox entitlements…"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_DIR"
fi

echo "Done: $APP_DIR"
echo "Mac App Store: archive in Xcode or use productbuild after Distribution signing."
