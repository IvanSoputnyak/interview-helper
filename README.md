# Interview Helper (Native macOS)

Standalone Mac App Store–ready menu bar app: capture a coding question, analyze with **your** OpenAI API key, view results on this Mac. The optional Node backend turns a phone or tablet into a **portable screen**: watch the Mac's screen live and have the AI solve and explain it from another room (see [Portable screen: how to use it](#portable-screen-how-to-use-it)).

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

- Node server + phone/tablet viewer on the same Wi‑Fi (`make start`, then open `h.local` on the phone). Share the Mac's screen from `/broadcast`, watch it live on the phone, and tap **Capture & analyze**; **Improve** and **Explain** work there too. The native Mac app works without it. Step-by-step: [Portable screen: how to use it](#portable-screen-how-to-use-it).

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
# Edit .env: OPENAI_API_KEY
make start
```

Other useful targets: `make all` (env + install + Swift build), `make test`, `make start`, `make dev`, `make package-mac`, `make clean`.  
Run `make` or `make help` for the full list.

## Setup (manual)

1. `npm install` (or `make install`)
2. `cp .env.example .env` (or `make env`)
3. Set `OPENAI_API_KEY`.
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
2. Open `.env` in a text editor and set `OPENAI_API_KEY=sk-…` (your OpenAI key).

### Each time you use it

1. **Start the server** on the Mac:
   ```bash
   make start
   ```
   It opens the share page (`http://localhost/broadcast`) in your browser and prints the phone address:
   ```
   Phone:  h.local   (if that does not open: http://192.168.0.185)
   Mac:    http://localhost/broadcast   (press Start sharing there)
   ```
   The first time, macOS may ask whether `node` may accept incoming connections: choose **Allow**, or the phone can't connect.
2. **Share the Mac's screen**: on the share page that opened, press **Start sharing**, pick the whole screen (or one window), and confirm.
   - Only the Mac itself can open the share page, and only at `http://localhost`: browsers allow screen sharing there, not on `h.local`.
   - Keep that tab in its own browser window. It can sit behind other windows, but don't minimize it or switch that window to another tab: browsers slow down hidden tabs and the phone's picture would freeze.
3. **Open the viewer on the phone/tablet**: in Safari or Chrome, type `h.local`. It is the same address every time, with nothing to copy. If the browser searches for it instead, type `h.local/`.
   - Tip: on iPhone/iPad tap **Share → Add to Home Screen** so it opens like an app next time.

### On the phone/tablet

- **Live screen**: the page opens on the Mac's screen, refreshed about once a second. The line under it says `Live · <time>` with the time of the last frame; if that time stops changing, the share has paused (see troubleshooting). Pinch to zoom in on small text.
- **Capture & analyze**: sends the newest frame to the AI. The answer appears below: a short summary, the code (numbered and colored like in an editor; swipe sideways on long lines), and time/memory, all in plain words. **Steps**, **Why this works** and **Example, step by step** are folded away; tap one to open it.
- **Explain**: a beginner-friendly walkthrough of the current answer (the idea with an everyday analogy, a small example traced step by step, why the slow approach is worse, common mistakes). It appears under **Explained simply**.
- **Improve**: asks the AI to re-check the answer for bugs, missed edge cases and speed, and replaces it with the improved version.

Several phones or tablets can watch at once; a new answer shows on all of them.

### If the connection drops

You don't need to reload anything; both pages recover on their own.

- **Wi‑Fi drops or the server restarts**: the phone and the Mac share page show **Connection lost · reconnecting…** in red and keep trying every few seconds. Once back, the share page says **Connected** and the phone's red line simply disappears. The phone then gets the latest answer and screen again, and the Mac keeps sharing (frames pause and resume; no need to press Start sharing again).
- **Phone was locked or you switched apps**: when you come back after 5 seconds or more, the viewer reconnects at once, so the picture is current within a second or two.
- **Frozen picture**: if no new frame arrives for 5 seconds, the line under the screen says **No new frame for …s** and why (reconnecting, or sharing on the Mac paused), so a frozen picture is never mistaken for live.
- **A button fails mid-request** (Capture & analyze, Improve, Explain): it's retried automatically up to 3 times (after 1, 2 and 4 seconds) and shows **Reconnecting (1/3)…**. If the phone is offline, it first shows **Waiting for connection…** and waits up to 30 seconds for the connection to return, then continues. Problems that retrying can't fix (such as a missing API key) are shown at once.
- **OpenAI is busy or rate-limited**: the server retries OpenAI twice by itself before reporting an error.
- **Not recovered automatically**: if you stop the share on the Mac, press **Start sharing** again: browsers require a click to share a screen.

**To stop**: press **Stop sharing** on the Mac (or the browser's own Stop button), then press `Ctrl+C` in the Terminal running the server.

### Privacy

- The live picture only travels over your Wi‑Fi, from the Mac to the server (also on the Mac) to your phone.
- Only the single frame you analyze goes to OpenAI.
- When you press **Stop sharing** or close the share tab, the server forgets the last frame and the phone clears the picture, so an old screen is never shown or analyzed later.
- There is no password: anyone on the same Wi‑Fi who opens `h.local` can watch the shared screen and tap the buttons (which spends your OpenAI credit). Use it on your home Wi‑Fi, not on café or office networks.
- Only the Mac running the server can share a screen or replace it; phones can only watch and ask.

### Troubleshooting

| Problem | Fix |
|---|---|
| Phone says the page can't be opened | Phone and Mac must be on the same Wi‑Fi (not guest Wi‑Fi). Check the server is still running. In **System Settings → Network → Firewall**, allow `node`. If `h.local` doesn't work (some Android phones), use the IP address `make start` prints next to it, for example `http://192.168.0.185`. |
| "Waiting for a shared screen…" on the phone | On the Mac, press **Start sharing** on the share page that `make start` opened. |
| The share page says screen sharing isn't available | You opened `h.local/broadcast` on the Mac. Use `http://localhost/broadcast`. |
| "Failed to start server" with `EADDRINUSE` | Something else already uses port 80 (or the server is already running in another Terminal). Stop it, or set `PORT=3000` in `.env`; the phone address then becomes `h.local:3000`. |
| "No new frame for …s (sharing on the Mac is paused)" | The share tab was hidden or minimized. Bring its window back on screen; frames resume within a second. |
| "Sharing stopped on the Mac" | Sharing was stopped or the share tab was closed. Press **Start sharing** on the Mac again. |
| "No new frame for …s (reconnecting)" or "Connection lost" that never clears | The server isn't running or the Wi‑Fi is down. Check the Terminal running `make start` and the phone's Wi‑Fi; the page reconnects by itself once it can. |
| "No shared screen yet" when tapping Capture & analyze | Start sharing on the Mac first. (Right after a server restart the phone retries this for a few seconds while the Mac reconnects.) |
| "OPENAI_API_KEY is missing." | Add the key to `.env` and restart the server (`Ctrl+C`, then `make start`). |
| Text in the analysis looks wrong | The AI sees the screen shrunk to at most 2048px on its longest side. Share a single window instead of a huge screen, or make the text bigger on the Mac, then capture again. |

## Environment variables

- `PORT` - server port (`80` default, so the phone opens plain `h.local`)
- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_MODEL` - model name (default: `defaultModel` in `shared/analysis-contract.json`, currently `gpt-6.1-sol`)
- `ANALYZE_PROMPT` - optional server-side default prompt used when a client omits `prompt`

## Commands

| Make | npm |
|------|-----|
| `make all` | (no single npm equivalent; runs env, install, swift-build) |
| `make mac-native` | `npm run mac:native` |
| `make start` | `npm start` (`make start` also opens the share page) |
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
