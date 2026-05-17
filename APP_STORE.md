# Mac App Store release (standalone app, no backend)

Interview Helper is now a **standalone menu bar app**: OpenAI calls run on-device, API key in Keychain, Q&A saved under `~/Library/Application Support/InterviewHelper/qa.jsonl`. No Node server required.

## Before you submit

1. **Apple Developer Program** — Mac App Store distribution membership.
2. **Bundle ID** — Register `com.interviewhelper.mac` (or change in `scripts/assemble-mac-app.sh` and `KeychainStore.service`).
3. **App Store Connect** — New macOS app, category e.g. Developer Tools.
4. **Screenshots** — Menu bar + results window + Settings (API key field blurred).
5. **Privacy** — App Privacy questionnaire: user-provided content sent to OpenAI (third party); not used for tracking. `PrivacyInfo.xcprivacy` is bundled.
6. **Review notes** — Explain: user supplies their own OpenAI API key; screen capture for interview questions; no server hosted by developer.

## Build for upload

```bash
make mac-icon
make package-mac          # release .app in dist/
# Or: bash scripts/assemble-mac-app.sh release
```

Sign for distribution (replace with your Apple Distribution identity):

```bash
codesign --deep --force --options runtime \
  --entitlements macos-native/InterviewHelperMac.entitlements \
  --sign "Apple Distribution: Your Name (TEAMID)" \
  dist/InterviewHelperMac.app
```

Create a Mac App Store `.pkg` in Xcode (**Product → Archive**) or Transporter, then upload.

## App capabilities

| Capability | Why |
|------------|-----|
| App Sandbox | Required for Mac App Store |
| Outgoing network | `api.openai.com` |
| Screen Recording | User prompt; usage string in Info.plist |

## Optional backend (not shipped)

The `server.js` stack remains in the repo for local dev / LAN viewer experiments. The store build does not start or require it.

## Version bumps

Edit `CFBundleShortVersionString` / `CFBundleVersion` in `scripts/assemble-mac-app.sh` before each submission.
