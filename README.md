# Interview Helper (Native macOS)

Standalone Mac App Store–ready menu bar app: capture a coding question, analyze with **your** OpenAI API key, view results on this Mac. Optional Node backend in the repo for LAN viewer experiments only.

## Features

- Native macOS tray app (Swift/AppKit), no Electron. Requires macOS 14+ (ScreenCaptureKit).
- Global hotkey: `Option + Shift + S`.
- Direct OpenAI vision API (no developer-hosted backend).
- API key stored in Keychain; minimal Q&A history on disk (`q` / `a` only).
- **Auto-reconnect**: network drops, timeouts, and OpenAI 408/429/5xx are retried up to 3× (1s/2s/4s backoff); when offline, waits up to 30s for the network first. Progress shows in the menu status / Improve button. Bad keys, 4xx, and `insufficient_quota` fail immediately.
- **Results window**: **Explain simply** adds a beginner walkthrough under the solution (idea + analogy, traced example, why not brute force, pitfalls; cached per answer, toggle Hide/Show); **Hide solution** collapses the answer to just the question (stays hidden for new captures until shown again); **Improve** reviews and fixes the solution.
- **Settings → Reasoning effort**: Default (model decides) / Low / Medium / High, applied to analyze, improve and explain.
- **Analysis prompt**: built-in default; optional custom prompt via menu.
- **Prompts + output schema live in one file**, [`shared/analysis-contract.json`](shared/analysis-contract.json), shared by the app and the Node server. After editing it run `make contract` (regenerates `AnalysisContract.generated.swift`); `make test` fails while the Swift copy is stale.
- **Mac App Store**: see [APP_STORE.md](APP_STORE.md).

### Optional dev backend (not required for the app)

- Node server + token-protected viewer for phone/tablet on the same Wi‑Fi (`npm start`). The native app does not talk to it; clients POST screenshots to `/api/analyze` with the viewer token.

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
4. Run the backend: `npm start` or `make start` (the native app is independent; see Quick start).

### “I don’t see the app”

Interview Helper is a **menu bar app** (like Wi‑Fi or Spotlight): it does **not** show in the Dock. Look at the **top-right of the screen** for **“IH”** next to the clock and click it for the menu. The first time you run it, an informational dialog explains this. When launched from Terminal, a line is also printed to stderr.

## Viewer

- `npm start` prints the viewer URL: `http://<this-mac>.local:<port>/viewer?token=<VIEWER_TOKEN>`.
- Open that full URL (including `?token=...`) on a phone/tablet on the same network.

## Environment variables

- `PORT` - server port (`3000` default)
- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_MODEL` - model name (default: `defaultModel` in `shared/analysis-contract.json`, currently `gpt-6.1-sol`)
- `ANALYZE_PROMPT` - optional server-side default prompt used when a client omits `prompt`
- `VIEWER_TOKEN` - token required for `/viewer`, `/api/analyze`, `/api/improve`, `/api/latest`, `/api/history`, `/api/qa`, and socket updates (random per start if unset)
- `HISTORY_MAX_ITEMS` - in-memory history and saved Q&A size (default `25`)
- `QA_STORE_PATH` - saved Q&A file (default `data/qa.jsonl`)

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

1. `codesign --force --options runtime --entitlements macos-native/InterviewHelperMac.entitlements --sign "Developer ID Application: <TEAM>" dist/InterviewHelperMac.app`
2. `ditto -c -k --keepParent dist/InterviewHelperMac.app dist/InterviewHelperMac.zip`
3. `xcrun notarytool submit dist/InterviewHelperMac.zip --keychain-profile "<PROFILE>" --wait`
4. `xcrun stapler staple dist/InterviewHelperMac.app`
