#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/InterviewHelperMac.app"

"$ROOT_DIR/scripts/assemble-mac-app.sh" release

echo ""
echo "Next steps for signing/notarization:"
echo "  1) codesign --deep --force --options runtime --sign \"Developer ID Application: <TEAM>\" \"$APP_DIR\""
echo "  2) ditto -c -k --keepParent \"$APP_DIR\" \"$ROOT_DIR/dist/InterviewHelperMac.zip\""
echo "  3) xcrun notarytool submit \"$ROOT_DIR/dist/InterviewHelperMac.zip\" --keychain-profile \"<PROFILE>\" --wait"
echo "  4) xcrun stapler staple \"$APP_DIR\""
