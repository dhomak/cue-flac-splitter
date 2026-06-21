# MusicTools.app (beta)

A native macOS shell around your Node/Express `music-tools` server, using the
system WebKit (WKWebView) instead of bundled Chromium. It launches
`node server.js` on a private localhost port, shows your existing web UI in a
real app window, and shuts the server down cleanly on quit.

Because `electron-main.js` uses no IPC (`nodeIntegration:false`, just
`loadURL`), this is a 1:1 swap for the Electron window — the directory browser,
SSE job streams, and every tool endpoint work unchanged over HTTP.

## Layout

```
MusicToolsApp/
  Package.swift
  Info.plist
  MusicTools.entitlements
  Sources/MusicTools/
    main.swift             NSApplication bootstrap + menu
    AppDelegate.swift      window, WKWebView, splash, folder-picker bridge
    ServerController.swift launches `node server.js`: port, PATH, health, teardown
    BundlePaths.swift      resolves Resources/server, server.js, node binary
  scripts/build_app.sh     compiles + assembles the .app
```

## One required change to server.js

`server.js` hardcodes `const PORT = 3000`. Make it honor the env var the
wrapper passes:

```js
const PORT = process.env.PORT || 3000;
```

The wrapper assigns a free port and health-checks that exact port; without this
edit node listens on 3000 and the window never loads. (If you'd rather not
touch server.js, hardcode `port = 3000` in ServerController instead — but
that collides with anything else on 3000.)

Nothing else in server.js needs changing. `process.resourcesPath` is undefined
under plain node, but your `__dirname` fallbacks already handle that, and the
build keeps the repo layout intact so scripts/vendor/pylibs resolve.

## Build

Requires Xcode Command Line Tools and Node on PATH (`brew install node`).

```sh
cd MusicToolsApp
./scripts/build_app.sh /path/to/your/music-tools     # dir containing server.js
open build/MusicTools.app                            # first launch: right-click -> Open
```

The script copies only what the app runs — your code, UI, `public/`, `pylibs`,
and the scripts — and **excludes** `node_modules`, `venv`, and `vendor` (those
hold ~250 MB of Electron plus your dev venv). It then installs production node
deps (`express`) and a slim Python venv with `mutagen`, `requests`,
`charset-normalizer`. Expect well under 100 MB, not 700+.

## Dev loop (no rebuild)

Run straight against your repo, with its live node_modules:

```sh
export MUSIC_TOOLS_SERVER_DIR=/abs/path/to/your/music-tools
swift run
```

Server logs: `~/Library/Logs/MusicTools/server.log`.

## Optional: native folder picker

Your browse buttons already work (they hit `/api/browse` server-side). If you
ever want a real macOS panel instead, post from JS:

```js
window.webkit.messageHandlers.musicTools.postMessage({ action: "pickFolder", target: "cue-path" });
```

The app opens an NSOpenPanel and writes the path back into `#cue-path`, firing
an `input` event.

## Distribution (what changes before family Macs)

The beta uses your system node and Homebrew ffmpeg. To ship to a clean Mac you
need Node and the binaries to travel. Two routes:

- **Bundle node** — uncomment the node-copy block in build_app.sh. Simple, but
  the node binary (~50-80 MB) eats much of the size win over Electron.
- **Compile server.js to one binary** — `bun build --compile server.js`
  (Bun runs Express), or `pkg` / Node SEA. Drop `node_modules` from the bundle,
  point `BundlePaths.node` at the compiled binary, and have it run that binary
  directly. This is where Swift+WebKit clearly beats Electron on size.

Then: re-add a `vendor/` (excluded from the beta) with static
ffmpeg/ffprobe in `vendor/bin/<arch>` (Homebrew's are dynamically linked and
won't run elsewhere) and a bundled python if you go that route, Developer ID
signing with
`--options runtime --entitlements MusicTools.entitlements`, and notarization
via notarytool + staple. Build per-arch (arm64 + Rosetta is simplest).

Unrelated cleanup: server.js still has a `/api/cue-convert` endpoint pointing at
`cue_converter.sh`. If you're dropping that tool, remove the endpoint and the
UI's "CUE Converter" tab too.
