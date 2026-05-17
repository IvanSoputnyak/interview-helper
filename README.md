# Interview Helper (Native macOS)

Standalone Mac App Store–ready menu bar app: capture a coding question, analyze with **your** OpenAI API key, view results on this Mac. Optional Node backend in the repo for LAN viewer experiments only.

## Features

- Native macOS tray app (Swift/AppKit), no Electron.
- Global hotkey: `Option + Shift + S`.
- Direct OpenAI vision API (no developer-hosted backend).
- API key stored in Keychain; minimal Q&A history on disk (`q` / `a` only).
- **Analysis prompt**: built-in default; optional custom prompt via menu.
- **Mac App Store**: see [APP_STORE.md](APP_STORE.md).

### Optional dev backend (not required for the app)

- Node server + token-protected viewer for phone/tablet on the same Wi‑Fi (`npm start`).

## Quick start (Makefile)

From the repo root:

```bash
make mac-app-debug   # recommended: real .app bundle + Screen Recording identity
open dist/InterviewHelperMac.app
# First launch: Settings → paste OpenAI API key → ⌥⇧S to capture
```

Or run from source: `make mac-native` (Swift only, no Node).

Optional backend + viewer:

```bash
make env && make install
# Edit .env: OPENAI_API_KEY, VIEWER_TOKEN
make start
```

Other useful targets: `make all` (env + install + Swift build), `make test`, `make start`, `make dev`, `make package-mac`, `make clean`.  
Run `make` or `make help` for the full list.

## Setup (manual)

1. `npm install` (or `make install`)
2. `cp .env.example .env` (or `make env`)
3. Set at least:
   - `OPENAI_API_KEY`
   - `VIEWER_TOKEN` (required for secure viewer access)
4. Run native app:
   - `npm run mac:native` or `make mac-native`

The native app attempts to start the backend automatically.  
If you prefer manual backend control, run `npm start` or `make start` first.

### “I don’t see the app”

Interview Helper is a **menu bar app** (like Wi‑Fi or Spotlight): it does **not** show in the Dock. Look at the **top-right of the screen** for **“IH”** next to the clock and click it for the menu. The first time you run it, an informational dialog explains this. When launched from Terminal, a line is also printed to stderr.

## Viewer

- Use menu bar **Open Viewer in Browser** or **Copy Viewer Link** (⌘⇧C).
- Share the full URL (including `?token=...`) to a phone/tablet on the same network.

## Environment variables

- `PORT` - server port (`3000` default)
- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_MODEL` - model name (default `gpt-4.1-mini`)
- `ANALYZE_PROMPT` - optional server-side default only if a client omits `prompt` (the native app always sends a prompt).
- `VIEWER_TOKEN` - token required for `/viewer`, `/api/latest`, `/api/history`, and socket updates
- `HISTORY_MAX_ITEMS` - in-memory history size (default `25`)
- `IH_PROJECT_ROOT` - path where the native app runs `npm start` from (optional)

## Commands

| Make | npm |
|------|-----|
| `make all` | (no single npm equivalent; runs env, install, swift-build) |
| `make mac-native` | `npm run mac:native` |
| `make start` | `npm start` |
| `make dev` | `npm run dev` |
| `make test` | `npm test` (Node API + Swift unit tests) |
| `make package-mac` | `npm run package:mac` |

## Packaging, signing, notarization

`make package-mac` (or `npm run package:mac`) builds a release Swift binary and creates:

- `dist/InterviewHelperMac.app`

Then sign + notarize (example):

1. `codesign --deep --force --options runtime --sign "Developer ID Application: <TEAM>" dist/InterviewHelperMac.app`
2. `ditto -c -k --keepParent dist/InterviewHelperMac.app dist/InterviewHelperMac.zip`
3. `xcrun notarytool submit dist/InterviewHelperMac.zip --keychain-profile "<PROFILE>" --wait`
4. `xcrun stapler staple dist/InterviewHelperMac.app`
