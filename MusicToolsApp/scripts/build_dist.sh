#!/bin/bash
# Builds a self-contained, arm64-only (Apple Silicon) MusicTools.app.
# No Intel, no Rosetta. Bundles arm64 Node + relocatable Python (+libs) +
# static arm64 ffmpeg, so the target Mac needs nothing installed.
#
#   ./scripts/build_dist.sh /path/to/your/music-tools
#
# Run on an Apple Silicon Mac (needs Xcode CLT, curl, npm).
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
APP_NAME="MusicTools"
SERVER_SRC="${1:?Usage: build_dist.sh /path/to/your/music-tools}"
ICON_SRC="${ICON_SRC:-/Users/aalien/sandbox/split-cue/build/icon.icns}"
NODE_VERSION="${NODE_VERSION:-v24.15.0}"     # LTS; bump from nodejs.org/dist
PY_LIBS="mutagen requests charset-normalizer"
DEV_ID="${DEV_ID:-}"                         # "Developer ID Application: Name (TEAMID)"; empty = ad-hoc

# arm64 everything
NODE_ARCH=arm64; PB_ARCH=aarch64; VARCH=arm64

[ -f "$SERVER_SRC/server.js" ] || { echo "error: no server.js in $SERVER_SRC" >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || echo "warning: host isn't arm64 — python/ffmpeg fetch expects an Apple Silicon Mac" >&2

WORK="$(pwd)/build"
APP="$WORK/$APP_NAME.app"
RES="$APP/Contents/Resources"
DEST="$RES/server"
VENDOR="$DEST/vendor"

# ── 1. Swift launcher (arm64) ────────────────────────────────────────────────
echo "==> swift build (arm64)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

# ── 2. Bundle skeleton ───────────────────────────────────────────────────────
echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$DEST" "$VENDOR/node/bin" "$VENDOR/python/$VARCH" "$VENDOR/bin/$VARCH"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
[ -f "$ICON_SRC" ] && cp "$ICON_SRC" "$RES/AppIcon.icns" || echo "warning: icon not found at $ICON_SRC"

# ── 3. Server files (no node_modules/venv/vendor/build) ──────────────────────
echo "==> copying server"
rsync -a --exclude node_modules --exclude venv --exclude vendor \
  --exclude build --exclude dist --exclude .git --exclude '*.log' --exclude .DS_Store \
  "$SERVER_SRC"/ "$DEST"/

# ── 4. Production node deps (express; no electron) ───────────────────────────
echo "==> npm production deps"
( cd "$DEST" && { npm ci --omit=dev 2>/dev/null || npm install --omit=dev --no-audit --no-fund; } )

# ── 5. Node runtime (arm64) ──────────────────────────────────────────────────
echo "==> bundling node $NODE_VERSION (arm64)"
NT="node-$NODE_VERSION-darwin-$NODE_ARCH"
curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/$NT.tar.gz" -o "$WORK/$NT.tar.gz"
tar -xzf "$WORK/$NT.tar.gz" -C "$WORK"
cp "$WORK/$NT/bin/node" "$VENDOR/node/bin/node"

# ── 6. Relocatable Python (aarch64) + libs ───────────────────────────────────
echo "==> bundling python-build-standalone (aarch64) + $PY_LIBS"
PB_URL="$(curl -fsSL https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
  | grep 'browser_download_url' | grep "${PB_ARCH}-apple-darwin-install_only.tar.gz\"" \
  | head -1 | cut -d'"' -f4)"
[ -n "$PB_URL" ] || { echo "error: couldn't locate python-build-standalone asset for $PB_ARCH" >&2; exit 1; }
curl -fsSL "$PB_URL" -o "$WORK/py.tar.gz"
rm -rf "$WORK/python"
tar -xzf "$WORK/py.tar.gz" -C "$WORK"          # extracts ./python
cp -R "$WORK/python/." "$VENDOR/python/$VARCH/"
PYBIN="$VENDOR/python/$VARCH/bin/python3"
"$PYBIN" -m pip install --quiet --upgrade pip
"$PYBIN" -m pip install --quiet $PY_LIBS

# ── 6b. Prune Python to runtime-only (saves ~30 MB uncompressed) ─────────────
echo "==> pruning Python (stdlib bloat, Tcl/Tk, pip, setuptools)"
PYLIB="$VENDOR/python/$VARCH/lib"
PYVER="$(ls "$PYLIB" | grep 'python3\.' | head -1)"   # e.g. python3.10

# stdlib modules never needed at runtime
for d in idlelib tkinter lib2to3 distutils ensurepip pydoc_data test unittest; do
  rm -rf "$PYLIB/$PYVER/$d"
done

# Tcl/Tk dylibs and support dirs
for item in libtcl9.0.dylib libtcl9tk9.0.dylib tcl9.0 tk9.0 itcl4.3.5 tcl9 thread3.0.4; do
  rm -rf "$PYLIB/$item"
done

# pip and setuptools not needed post-install
rm -rf "$PYLIB/$PYVER/site-packages/pip" \
       "$PYLIB/$PYVER/site-packages/pip-"*.dist-info \
       "$PYLIB/$PYVER/site-packages/setuptools" \
       "$PYLIB/$PYVER/site-packages/setuptools-"*.dist-info \
       "$PYLIB/$PYVER/site-packages/_distutils_hack" \
       "$PYLIB/$PYVER/site-packages/distutils-precedence.pth"

# Unused bin entries (keep python, python3, python3.x only)
for b in idle3 idle3.10 2to3 2to3-3.10 pip3 pip3.10 pydoc3 pydoc3.10 \
          python3-config python3.10-config; do
  rm -f "$VENDOR/python/$VARCH/bin/$b"
done

# Bytecode caches (not needed; Python regenerates on first import)
find "$VENDOR/python/$VARCH" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# ── 7. Static arm64 ffmpeg + ffprobe (via npm, host-arch builds) ─────────────
echo "==> bundling static arm64 ffmpeg + ffprobe"
FFTMP="$WORK/fftmp"; rm -rf "$FFTMP"; mkdir -p "$FFTMP"
( cd "$FFTMP" && npm init -y >/dev/null 2>&1 && npm install ffmpeg-ffprobe-static --no-save --no-audit --no-fund >/dev/null 2>&1 )
FFDIR="$FFTMP/node_modules/ffmpeg-ffprobe-static"
ff_ok=1
for tool in ffmpeg ffprobe; do
  src="$(find "$FFDIR" -maxdepth 2 -type f -name "$tool" 2>/dev/null | head -1 || true)"
  if [ -n "$src" ]; then cp "$src" "$VENDOR/bin/$VARCH/$tool"; chmod +x "$VENDOR/bin/$VARCH/$tool"; else ff_ok=0; fi
done
if [ "$ff_ok" = 0 ]; then
  echo "  !! ffmpeg/ffprobe not fetched. Drop arm64 static builds into $VENDOR/bin/$VARCH/ and re-run."
  echo "     Fallback source: https://osxexperts.net/"
fi

# ── 8. Sign ──────────────────────────────────────────────────────────────────
if [ -n "$DEV_ID" ]; then
  echo "==> signing nested binaries + app with Developer ID (hardened runtime)"
  find "$RES" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) -print0 \
    | while IFS= read -r -d '' f; do
        codesign --force --timestamp --options runtime --sign "$DEV_ID" "$f" 2>/dev/null || true
      done
  codesign --force --deep --timestamp --options runtime \
    --entitlements MusicTools.entitlements --sign "$DEV_ID" "$APP"
  echo "    signed. Next: notarize + staple (see DISTRIBUTION.md)."
else
  echo "==> ad-hoc signing (no notarization)"
  codesign --force --deep --sign - "$APP"
  echo "    Recipients clear quarantine once: xattr -dr com.apple.quarantine MusicTools.app"
fi

echo ""
du -sh "$APP"
echo "Built $APP  (arm64 / Apple Silicon only)"
