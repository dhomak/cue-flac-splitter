# Music Tools — project guide

Two parts that ship as one macOS app:

1. **music-tools** — a Node/Express server (`server.js`) with a browser UI
   (`index.html`, React-via-Babel) that shells out to media scripts and streams
   their stdout back over SSE.
2. **MusicToolsApp/** — a native **arm64-only** Swift/WKWebView shell that
   launches the Node server and shows the UI in a real app window (replaces an
   earlier Electron build to drop the bundled Chromium).

## Architecture

- `server.js` (Express): serves `index.html` **fresh on every request** (so UI
  edits show on reload, no rebuild). Endpoints under `/api/*` spawn the scripts
  and register SSE jobs (`/stream/:jobId`). Reads `PORT` and `MUSIC_ROOT` from
  env. Resolves bundled tools via `process.resourcesPath || __dirname` →
  `vendor/`. Directory browsing is server-side via `/api/browse`.
- Swift wrapper (`MusicToolsApp/Sources/MusicTools/`):
  - `ServerController.swift` launches `node server.js`, **detects the port from
    node's stdout** (`http://localhost:<port>`) and health-checks it, then tears
    the process down (SIGTERM→SIGKILL) on quit.
  - `AppDelegate.swift` hosts the `WKWebView`, shows a splash until ready, and
    bridges a **native folder picker**.
  - `BundlePaths.swift` resolves `vendor/node`, `server.js`, logs.
- Tools: `audio_lyrics_fetcher.py`, `encoding_fixer.py` (also handles `.cue`
  → UTF-8 via charset_normalizer), `split-cue-unicode.pl`, `flac_downsampler.sh`.

## Conventions / decisions (don't regress these)

- **arm64 only, no Rosetta.** All bundled runtimes (node, python, ffmpeg) are
  arm64. The app is not meant to run on Intel.
- `server.js` must use `const PORT = process.env.PORT || 3000;` so the wrapper
  can assign a free port. Do not enable the Flask/Express reloader.
- `index.html` is served live — reload to test UI changes; only rebuild the
  `.app` for Swift changes.
- **Removed features (keep removed):** the "CUE Converter" tool (UI nav, panel,
  `runCueConv`, the `/api/cue-convert` route, and `cue_converter*.sh`) — `.cue`
  conversion now lives in `encoding_fixer.py`. The "Logout" button (it led to a
  dead `/login` page). The CUE **Splitter** is a different tool — keep it.
- Native folder picker: JS posts
  `window.webkit.messageHandlers.musicTools.postMessage({action:'pickFolder', target:<inputId>})`;
  Swift opens `NSOpenPanel` and writes the path back. Falls back to the in-page
  `/api/browse` modal in a plain browser.

## Build / package (run from the music-tools repo root)

```sh
# Beta on this machine (uses system node + Homebrew ffmpeg)
./MusicToolsApp/scripts/build_app.sh .

# Self-contained arm64 distributable (bundles node + python + ffmpeg)
./MusicToolsApp/scripts/build_dist.sh .

# Drag-to-Applications DMG (run after build_dist.sh)
./MusicToolsApp/scripts/package_dmg.sh
```

Signing/notarization knobs (env vars on the dist + dmg scripts):
`DEV_ID="Developer ID Application: NAME (TEAMID)"`, `NOTARY_PROFILE=<profile>`.
Full order in `MusicToolsApp/DISTRIBUTION.md`. Icon source defaults to
`/Users/aalien/sandbox/split-cue/build/icon.icns` (override with `ICON_SRC=`).

## Bundle layout (distributable)

```
MusicTools.app/Contents/Resources/server/
  server.js  index.html  public/  <scripts>  node_modules/   (express only)
  vendor/
    node/bin/node                arm64 Node
    python/arm64/bin/python3     relocatable Python + mutagen/requests/charset-normalizer
    bin/arm64/ffmpeg, ffprobe    static arm64 (fetched via ffmpeg-ffprobe-static)
```

## Gotchas

- A Finder-launched `.app` gets a minimal `PATH`; node/ffmpeg/python are found
  via the env `server.js` builds (`SPAWN_ENV`) and the wrapper's `PATH` for node.
- macOS caches app icons — re-launch or `killall Dock` after an icon change.
- For notarization, every Mach-O in `vendor/` must be signed inside-out; a
  rejection is almost always one unsigned nested binary.
- ffmpeg static builds are GPL/LGPL — fine for family, note it for public use.
