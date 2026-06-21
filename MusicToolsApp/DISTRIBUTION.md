# Distributing MusicTools.app (arm64 / Apple Silicon only)

This build targets Apple Silicon exclusively — no Intel, no Rosetta. It bundles
everything a clean Mac lacks, so the target machine needs nothing installed:

```
Resources/server/vendor/
  node/bin/node                 arm64 Node runtime
  python/arm64/bin/python3      relocatable arm64 Python + mutagen/requests/charset-normalizer
  bin/arm64/ffmpeg, ffprobe     static arm64 media binaries
```

`server.js` resolves `vendor/python/<arch>` and `vendor/bin/<arch>`;
`BundlePaths.swift` resolves `vendor/node`. On arm64 they all point at the dirs
above.

## Build

```sh
./scripts/build_dist.sh /path/to/your/music-tools
```

Run on an Apple Silicon Mac (Xcode CLT, curl, npm). It:

1. builds the Swift launcher for arm64,
2. copies your server + production node deps (express; no electron),
3. downloads arm64 Node (LTS) into `vendor/node`,
4. downloads a relocatable arm64 Python and pip-installs the three libs,
5. fetches static arm64 `ffmpeg`/`ffprobe` via the `ffmpeg-ffprobe-static`
   npm package (host-arch builds, so arm64 on your Mac),
6. signs.

It's a fully native arm64 build — nothing runs under Rosetta. The resulting app
won't launch on Intel Macs by design.

Knobs: `NODE_VERSION` (bump from nodejs.org/dist) and `DEV_ID` (below).

## Signing

- **Ad-hoc (default, `DEV_ID` unset).** Works, but each recipient clears the
  quarantine flag once:
  - right-click the app → **Open** → confirm, or
  - `xattr -dr com.apple.quarantine /Applications/MusicTools.app`

- **Developer ID (`DEV_ID` set).** Proper signing with the hardened runtime,
  ready to notarize:

  ```sh
  DEV_ID="Developer ID Application: Your Name (TEAMID)" \
    ./scripts/build_dist.sh /path/to/your/music-tools
  ```

## Notarization (needs an Apple Developer account, $99/yr)

After a `DEV_ID` build:

```sh
xcrun notarytool store-credentials musictools-profile \
  --apple-id you@example.com --team-id TEAMID         # one-time

ditto -c -k --keepParent build/MusicTools.app build/MusicTools.zip
xcrun notarytool submit build/MusicTools.zip --keychain-profile musictools-profile --wait
xcrun stapler staple build/MusicTools.app
```

Notarized, the app opens with a plain double-click on any Apple Silicon Mac.
If notarytool rejects it, it's almost always one unsigned nested binary in
`vendor/` — re-check that every Mach-O got signed.

## ffmpeg licensing

The static ffmpeg builds are GPL/LGPL. Fine for sharing with family; relevant
only for public/commercial distribution.

## Packaging as a DMG

After building the app, wrap it in a drag-to-Applications disk image:

```sh
./scripts/build_dist.sh /path/to/your/music-tools
./scripts/package_dmg.sh
# -> build/MusicTools.dmg
```

`package_dmg.sh` stages the app next to an `/Applications` symlink and builds a
compressed DMG with `hdiutil` (no extra tools needed). The recipient mounts it
and drags Music Tools into Applications.

### Ad-hoc DMG

Just run the two commands above. After dragging the app to Applications, each
recipient clears quarantine once (right-click → Open, or
`xattr -dr com.apple.quarantine /Applications/MusicTools.app`).

### Signed + notarized DMG (Developer ID)

Order matters — notarize and staple the **app** first, then the **DMG**:

```sh
# 1. signed app
DEV_ID="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/build_dist.sh /path/to/your/music-tools

# 2. notarize + staple the app
ditto -c -k --keepParent build/MusicTools.app build/MusicTools-app.zip
xcrun notarytool submit build/MusicTools-app.zip --keychain-profile musictools-profile --wait
xcrun stapler staple build/MusicTools.app

# 3. build, sign, notarize + staple the DMG
DEV_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=musictools-profile \
  ./scripts/package_dmg.sh
```

Stapling the app (step 2) means it stays notarized once copied out of the DMG;
stapling the DMG (step 3) means the image itself opens cleanly. The result is a
double-click install on any Apple Silicon Mac.

### Prettier DMG (optional)

For a styled image — custom background, positioned icons — use `create-dmg`
(`brew install create-dmg`) instead of `package_dmg.sh`:

```sh
create-dmg --volname "Music Tools" --app-drop-link 480 220 \
  --window-size 640 400 build/MusicTools.dmg build/MusicTools.app
```
