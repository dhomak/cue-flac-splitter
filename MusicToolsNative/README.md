# Music Tools — native (pure Swift)

A SwiftUI macOS app — no Node, no Express, no WKWebView. The app *is* the UI:
it spawns media scripts as subprocesses *or* runs tools natively in-process,
streaming all output into a native console.

Layout mirrors the old web UI: a sidebar of tools → a panel with that tool's
options as native controls → a live console.

## Tools → scripts

| Panel            | Script                   | Runtime |
|------------------|--------------------------|---------|
| FLAC Downsampler | flac_downsampler.sh      | bash    |
| CUE Splitter     | split-cue-unicode.pl     | perl    |
| Lyrics Fetcher   | native (LyricsFetcher.swift) | Swift   |
| Encoding Fixer   | encoding_fixer.py        | python  |

`Paths.swift` builds each subprocess command + environment (PATH with bundled
ffmpeg, `PYTHONPATH=pylibs`). `LyricsFetcher.swift` + `TagReader.swift` run
in-process via `ToolRunner.runNative()` — no Python, no subprocess, no network
library beyond `URLSession`.

## Build

```sh
# Beta (this machine): uses system python3 / ffmpeg / perl
./scripts/build_app.sh /path/to/your/music-tools

# Distributable arm64 (bundles python + ffmpeg; perl stays system)
./scripts/build_dist.sh /path/to/your/music-tools
```

`/path/to/your/music-tools` just needs the 3 scripts (and `pylibs/`).

## Dev loop (no rebuild)

```sh
MUSIC_TOOLS_DEV_REPO=/abs/path/to/your/music-tools swift run
```

Runs against the scripts in that repo directly. Edit a panel's controls in
Swift, re-run.

## Bundle layout (distributable)

```
MusicTools.app/Contents/Resources/
  scripts/   flac_downsampler.sh  split-cue-unicode.pl  encoding_fixer.py
  pylibs/    vendored pure-python deps
  vendor/python/arm64/bin/python3   relocatable Python + mutagen/charset-normalizer
  vendor/bin/arm64/ffmpeg, ffprobe  static arm64
```

## Notes / what's left

- **Perl** still comes from `/usr/bin/perl` (present on macOS, Apple-deprecated).
  Everything else is bundled. To be fully self-contained, bundle perl via
  PAR::Packer later.
- **Theming** approximates the old cyberpunk look with dark mode + a cyan accent
  and monospaced console. To match it fully (Orbitron/Share Tech Mono, chamfered
  panels), add the font files to the bundle and a custom panel style.
- Signing / notarization / DMG: same flow as the web-wrapper version — set
  `DEV_ID` on `build_dist.sh`, then notarize + staple (see the wrapper's
  DISTRIBUTION.md), and package with `hdiutil`/`create-dmg`.
