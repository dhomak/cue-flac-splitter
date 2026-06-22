# Music Tools

A cyberpunk-themed macOS audio toolkit. Native arm64 app — no Electron, no bundled Chromium. Ships as two alternative frontends around the same set of scripts:

- **MusicToolsApp** — Swift/WKWebView shell that launches a local Node/Express server and shows the existing web UI in a native window
- **MusicToolsNative** — pure SwiftUI app that spawns each script directly; no Node required

Both are Apple Silicon only (arm64). Pre-built distributable DMGs bundle Node/Python/ffmpeg so nothing needs to be installed on the target Mac.

---

## Tools

| Tool | Script | What it does |
|---|---|---|
| **FLAC Downsampler** | `flac_downsampler.sh` | Convert hi-res FLAC to 44.1 kHz / 16-bit via ffmpeg + SoXR |
| **CUE Splitter** | `split-cue-unicode.pl` | Split single-file FLAC+CUE albums into tracks — full Unicode / Cyrillic support |
| **Lyrics Fetcher** | `audio_lyrics_fetcher.py` | Fetch synced (.lrc) or plain (.txt) lyrics for FLAC/MP3/M4A via LRCLIB, ChartLyrics, lyrics.ovh |
| **Encoding Fixer** | `encoding_fixer.py` | Repair Windows-1251 mojibake in .cue/.txt/.log/.nfo/.m3u files and MP3 ID3 tags; also converts .cue to UTF-8. Dry-run by default |
| **Magnet Scraper** | `rutracker_scraper.py` | Extract magnet links from RuTracker topic URLs |

---

## Install from DMG (recommended)

Build a self-contained DMG (see Build section), then:

```bash
# Mount and drag Music Tools to Applications, then clear quarantine:
xattr -cr /Applications/MusicTools.app
open /Applications/MusicTools.app
```

---

## Run the dev server (browser or MusicToolsApp)

Requires Node 18+, ffmpeg (`brew install ffmpeg`), Perl, Python 3, and:

```bash
pip3 install mutagen requests charset-normalizer
```

```bash
npm install
npm start                        # Express on :3000
open http://localhost:3000       # or launch MusicToolsApp in dev mode (see below)

MUSIC_ROOT=/Volumes/Music npm start   # custom music root
```

---

## Build

All build scripts live in `MusicToolsApp/scripts/` and `MusicToolsNative/scripts/`. Run from the repo root.

### MusicToolsApp (WKWebView + Node server)

```bash
# Beta: uses system node + Homebrew ffmpeg
./MusicToolsApp/scripts/build_app.sh .

# Self-contained arm64 distributable (bundles node, python, ffmpeg)
./MusicToolsApp/scripts/build_dist.sh .

# Wrap the distributable in a drag-to-Applications DMG
./MusicToolsApp/scripts/package_dmg.sh
```

### MusicToolsNative (pure SwiftUI, no Node)

```bash
# Beta: uses system python3 / ffmpeg / perl
./MusicToolsNative/scripts/build_app.sh .

# Self-contained arm64 distributable (bundles python, ffmpeg)
./MusicToolsNative/scripts/build_dist.sh .
```

Signing/notarization: set `DEV_ID="Developer ID Application: NAME (TEAMID)"` and optionally `NOTARY_PROFILE=<profile>` before the dist/dmg scripts. Full order in [`MusicToolsApp/DISTRIBUTION.md`](MusicToolsApp/DISTRIBUTION.md).

---

## CLI scripts

All scripts work standalone without any GUI.

```bash
# Split a FLAC+CUE album
./split-cue-unicode.pl --to-root --delete --dry-run /path/to/album
./split-cue-unicode.pl --to-root --delete /path/to/album

# Downsample to CD quality
./flac_downsampler.sh /path/to/hires /path/to/output

# Fetch lyrics (synced .lrc preferred; --prefer-txt to force plain)
python3 audio_lyrics_fetcher.py /path/to/album
python3 audio_lyrics_fetcher.py /path/to/album --prefer-txt

# Fix mojibake in text/cue/tag files
python3 encoding_fixer.py /path/to/album              # dry-run preview
python3 encoding_fixer.py /path/to/album --apply
python3 encoding_fixer.py /path/to/album --apply --backup --verbose
```

---

## Project layout

```
server.js                   Express backend — SSE job streaming, /api/* routes
index.html                  Single-page web UI (React via Babel, served live)
split-cue-unicode.pl        CUE splitter
flac_downsampler.sh         FLAC downsampler
audio_lyrics_fetcher.py     Lyrics fetcher
encoding_fixer.py           Mojibake / encoding repair
rutracker_scraper.py        Magnet link extractor

MusicToolsApp/              Swift/WKWebView shell + build scripts
MusicToolsNative/           Pure SwiftUI app + build scripts
```

---

## Notes

- **arm64 only.** Bundled runtimes (node, python, ffmpeg) are all Apple Silicon; the app will not run under Rosetta.
- `server.js` picks up `PORT` from the environment — the Swift wrapper assigns a free port and health-checks it.
- macOS caches app icons — run `killall Dock` after an icon change.
- Static ffmpeg builds are GPL/LGPL — fine for personal use.

---

## License

MIT
