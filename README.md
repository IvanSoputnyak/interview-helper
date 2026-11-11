# Interview Helper (Native macOS)

Standalone Mac App Store–ready menu bar app: capture a coding question, analyze with **your** OpenAI API key, view results on this Mac. The optional Node backend turns a phone or tablet into a **portable screen**: watch the Mac's screen live and ask the AI about it from another room (see [Portable screen: how to use it](#portable-screen-how-to-use-it)).

## Features

- Native macOS tray app (Swift/AppKit), no Electron. Requires macOS 14+ (ScreenCaptureKit).
- Global hotkey: `Option + Shift + S` (captures the display under the cursor, leaving out Interview Helper's own windows; downscaled to 2048px). If another app already owns the shortcut, the menu item says "hotkey unavailable" and still works.
- Direct OpenAI vision API (no developer-hosted backend).
- API key stored in Keychain; minimal Q&A history on disk (question, answer code, id, timestamp), viewable via menu **Show history** or the **History** button.
- **Auto-reconnect**: network drops and OpenAI 408/429/5xx are retried up to 3× (1s/2s/4s backoff); timeouts (client or 504) are retried only once, since a slow reasoning answer already waited the full 180s; when offline, waits up to 30s for the network first. Progress shows in the menu status and on the Improve / Explain buttons. Bad keys, other 4xx, and `insufficient_quota` fail immediately.
- **Results window**: **Explain simply** adds a beginner walkthrough under the solution (idea + analogy, traced example, why not brute force, pitfalls; cached per answer, toggle Hide/Show); **Hide solution** collapses the answer to just the question (stays hidden for new captures until shown again); **Improve** reviews and fixes the solution.
- **Settings**: OpenAI API key; **Model** (blank = default from `shared/analysis-contract.json`); **Reasoning effort** Default (model decides) / Low / Medium / High, applied to analyze, improve and explain; **History size** (Q&A rows kept and shown in History, 1–500, default 25; blank or invalid means 25; lowering it hides older rows at once and removes them from disk on the next capture).
- **Analysis prompt**: built-in default; optional custom prompt via menu.
- **Prompts + output schema live in one file**, [`shared/analysis-contract.json`](shared/analysis-contract.json), shared by the app and the Node server. After editing it run `make contract` (regenerates `AnalysisContract.generated.swift`); `make test` fails while the Swift copy is stale.
- **Mac App Store**: see [APP_STORE.md](APP_STORE.md).

### Optional backend: portable screen (not required for the Mac app)

- Node server + token-protected viewer for phone/tablet on the same Wi‑Fi (`npm start`). Share the Mac's screen from `/broadcast`, watch it live on the phone, and tap **Capture & analyze** (optionally with a question about what's on screen); **Improve** and **Explain simply** work there too. The native Mac app works without it. Step-by-step: [Portable screen: how to use it](#portable-screen-how-to-use-it).

## Quick start (Makefile)

From the repo root:

```bash
make mac-app-debug   # recommended: builds the real .app bundle (Screen Recording identity) and opens it
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

Interview Helper is a **menu bar app** (like Wi‑Fi or Spotlight): it does **not** show in the Dock. Look at the **top-right of the screen** for **“IH”** next to the clock and click it for the menu. The first time you run it, an informational dialog explains this. When run directly from Terminal (e.g. `make mac-native`), a line is also printed to stderr.

## Portable screen: how to use it

See the Mac's screen live on a phone or tablet anywhere on the same Wi‑Fi, and have the AI read and explain it with one tap.

```
Mac (share page) ──about 1 frame/sec──▶ server on the Mac ──▶ phone/tablet viewer
                                              │
                         tap "Capture & analyze" → latest frame → OpenAI → answer on the phone
```

### One-time setup (on the Mac)

1. Install Node.js (version 20 or newer, from nodejs.org), then from the repo folder run:
   ```bash
   make env && make install
   ```
2. Open `.env` in a text editor and set:
   - `OPENAI_API_KEY=sk-…` (your OpenAI key)
   - `VIEWER_TOKEN=` any long password you choose. Set it so the links stay the same every time; if it is empty, a new random token is made on every start and old links stop working.
3. Find the Mac's network name: **System Settings → General → Sharing → Local hostname** (for example `Johns-MacBook.local`), or run `scutil --get LocalHostName` in Terminal and add `.local`.

### Each time you use it

1. **Start the server** on the Mac:
   ```bash
   make start
   ```
   It prints two links, for example:
   ```
   Viewer (phone/tablet): http://<this-mac>.local:3000/viewer?token=YOUR_TOKEN
   Share this Mac's screen (open on this Mac): http://localhost:3000/broadcast?token=YOUR_TOKEN
   ```
   The first time, macOS may ask whether `node` may accept incoming connections: choose **Allow**, or the phone can't connect.
2. **Share the Mac's screen**: on the Mac, open the **share** link in Chrome or Safari, press **Start sharing**, pick the whole screen (or one window), and confirm.
   - Use the link exactly as printed, starting with `http://localhost`. Browsers only allow screen sharing on `localhost`, not on the `.local` address.
   - Keep that tab in its own browser window. It can sit behind other windows, but don't minimize it or switch that window to another tab: browsers slow down hidden tabs and the phone's picture would freeze.
3. **Open the viewer on the phone/tablet**: in Safari or Chrome, open the **viewer** link, replacing `<this-mac>` with the name from setup step 3 (for example `http://Johns-MacBook.local:3000/viewer?token=YOUR_TOKEN`).
   - Tip: on iPhone/iPad tap **Share → Add to Home Screen** so it opens like an app next time.

### On the phone/tablet

- **Live screen**: the top card shows the Mac's screen, refreshed about once a second. The line under it says `Live · <time>` with the time of the last frame; if that time stops changing, the share has paused (see troubleshooting). Pinch to zoom in on small text.
- **Capture & analyze**: sends the newest frame to the AI. The answer fills in **Summary**, **Suggested Solution**, **Code Snippet**, complexity, and a short walkthrough.
  - To ask about something specific, type it in **"Optional: ask about what's on screen"** first (for example "why is this O(n)?" or "what does line 4 do?"). The AI answers your question in **Summary** and still solves the problem on screen. Leave it empty for a full solution.
- **Explain simply**: a beginner-friendly walkthrough of the current answer (the idea with an everyday analogy, a small example traced step by step, why the slow approach is worse, common mistakes). It appears in the **Explained simply** card.
- **Improve solution**: asks the AI to re-check the answer for bugs, missed edge cases and speed, and replaces it with the improved version.
- **Saved Q&A**: past questions and answers (the last 25 by default, `HISTORY_MAX_ITEMS`).

Several phones or tablets can watch at once; a new answer shows on all of them.

### If the connection drops

You don't need to reload anything; both pages recover on their own.

- **Wi‑Fi drops or the server restarts**: the phone and the Mac share page show **Connection lost · reconnecting…** in red, keep trying every few seconds, and switch back to **Connected** by themselves. The phone then gets the latest answer, history and screen again, and the Mac keeps sharing (frames pause and resume; no need to press Start sharing again).
- **Phone was locked or you switched apps**: when you come back after 5 seconds or more, the viewer reconnects at once, so the picture is current within a second or two.
- **Frozen picture**: if no new frame arrives for 5 seconds, the line under the screen says **No new frame for …s** and why (reconnecting, or sharing on the Mac paused or stopped), so a frozen picture is never mistaken for live.
- **A button fails mid-request** (Capture & analyze, Improve, Explain simply): it's retried automatically up to 3 times (after 1, 2 and 4 seconds) and shows **Reconnecting (1/3)…**. If the phone is offline, it first shows **Waiting for connection…** and waits up to 30 seconds for the connection to return, then continues. Problems that retrying can't fix (wrong token, missing API key) are shown at once.
- **OpenAI is busy or rate-limited**: the server retries OpenAI twice by itself before reporting an error.
- **Not recovered automatically**: if the token changes (for example `VIEWER_TOKEN` was empty and the server restarted with a new random one), open the new link. Also, if you stop the share on the Mac, press **Start sharing** again: browsers require a click to share a screen.

**To stop**: press **Stop sharing** on the Mac (or the browser's own Stop button), then press `Ctrl+C` in the Terminal running the server.

### Privacy

- The live picture only travels over your Wi‑Fi, from the Mac to the server (also on the Mac) to your phone.
- Only the single frame you analyze goes to OpenAI, with your question.
- Every page and request needs the token, so keep the viewer link private.

### Troubleshooting

| Problem | Fix |
|---|---|
| Phone says the page can't be opened | Phone and Mac must be on the same Wi‑Fi (not guest Wi‑Fi). Check the server is still running. In **System Settings → Network → Firewall**, allow `node`. If the `.local` name doesn't work (some Android phones), use the Mac's IP instead: run `ipconfig getifaddr en0` on the Mac and open `http://<that-ip>:3000/viewer?token=…`. |
| "Invalid viewer token" | The token in the link doesn't match `VIEWER_TOKEN` in `.env` (or the server restarted with a new random token). Copy the link again from the server output. |
| "Waiting for a shared screen…" on the phone | On the Mac, open the **share** link and press **Start sharing**. |
| The share page says screen sharing isn't available | You opened the `.local` link on the Mac. Use the `http://localhost:3000/broadcast?token=…` link. |
| "No new frame for …s (sharing on the Mac is paused or stopped)" | The share tab was hidden or minimized, or sharing was stopped. Bring its window back on screen (frames resume within a second), or press **Start sharing** again. |
| "No new frame for …s (reconnecting)" or "Connection lost" that never clears | The server isn't running or the Wi‑Fi is down. Check the Terminal running `make start` and the phone's Wi‑Fi; the page reconnects by itself once it can. |
| "No shared screen yet" when tapping Capture & analyze | Start sharing on the Mac first. (Right after a server restart the phone retries this for a few seconds while the Mac reconnects.) |
| "OPENAI_API_KEY is missing." | Add the key to `.env` and restart the server (`Ctrl+C`, then `make start`). |
| Text in the analysis looks wrong | The AI sees the screen shrunk to at most 2048px on its longest side. Share a single window instead of a huge screen, or make the text bigger on the Mac, then capture again. |

## Environment variables

- `PORT` - server port (`3000` default)
- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_MODEL` - model name (default: `defaultModel` in `shared/analysis-contract.json`, currently `gpt-6.1-sol`)
- `ANALYZE_PROMPT` - optional server-side default prompt used when a client omits `prompt`
- `VIEWER_TOKEN` - token required for `/viewer`, `/broadcast`, every `/api/*` route except `/api/health`, and the socket (random per start if unset)
- `HISTORY_MAX_ITEMS` - saved Q&A size (default `25`)
- `QA_STORE_PATH` - saved Q&A file (default `data/qa.jsonl`)

## Commands

| Make | npm |
|------|-----|
| `make all` | (no single npm equivalent; runs env, install, swift-build) |
| `make mac-native` | `npm run mac:native` |
| `make start` | `npm start` |
| `make dev` | `npm run dev` |
| `make test` | `npm test` (Node API + Swift unit tests; Swift tests build in `~/Library/Caches/InterviewHelper/swift-test`, because iCloud-synced Desktop/Documents folders tag build output and codesign then rejects the test bundle — override with `SWIFT_TEST_BUILD`) |
| `make package-mac` | `npm run package:mac` |

## Packaging, signing, notarization

`make package-mac` (or `npm run package:mac`) builds a release Swift binary and creates:

- `dist/InterviewHelperMac.app`

Then sign + notarize (example):

1. `codesign --force --options runtime --entitlements macos-native/InterviewHelperMac.entitlements --sign "Developer ID Application: <TEAM>" dist/InterviewHelperMac.app`
2. `ditto -c -k --keepParent dist/InterviewHelperMac.app dist/InterviewHelperMac.zip`
3. `xcrun notarytool submit dist/InterviewHelperMac.zip --keychain-profile "<PROFILE>" --wait`
4. `xcrun stapler staple dist/InterviewHelperMac.app`
