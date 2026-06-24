#!/bin/bash
# Self-contained, arm64-only MusicTools.app — bundles Python + ffmpeg. No Node.
# (Perl still comes from the system /usr/bin/perl.)
#   ./scripts/build_dist.sh /path/to/your/music-tools
set -euo pipefail
APP_NAME="MusicTools"
REPO="${1:?Usage: build_dist.sh /path/to/your/music-tools}"
ICON_SRC="${ICON_SRC:-/Users/aalien/sandbox/split-cue/build/icon.icns}"
PY_LIBS="mutagen charset-normalizer"
DEV_ID="${DEV_ID:-}"
PB_ARCH=aarch64; VARCH=arm64
SCRIPTS=(flac_downsampler.sh split-cue-unicode.pl encoding_fixer.py)
[ "$(uname -m)" = arm64 ] || echo "warning: host isn't arm64" >&2

# Locate the scripts up front and fail fast.
SRC=""
for cand in "$REPO" "$REPO/scripts"; do
  [ -f "$cand/flac_downsampler.sh" ] && { SRC="$cand"; break; }
done
if [ -z "$SRC" ]; then
  echo "error: scripts not found under '$REPO' (looked in ./ and ./scripts/)." >&2
  echo "       Point this at the directory that contains: ${SCRIPTS[*]}" >&2
  exit 1
fi
missing=(); for s in "${SCRIPTS[@]}"; do [ -f "$SRC/$s" ] || missing+=("$s"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "error: these scripts are missing from '$SRC': ${missing[*]}" >&2
  exit 1
fi
echo "==> scripts: $SRC"

WORK="$(pwd)/build"; APP="$WORK/$APP_NAME.app"; RES="$APP/Contents/Resources"; VENDOR="$RES/vendor"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$RES/scripts" "$VENDOR/python/$VARCH" "$VENDOR/bin/$VARCH"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"; cp Info.plist "$APP/Contents/Info.plist"
[ -f "$ICON_SRC" ] && cp "$ICON_SRC" "$RES/AppIcon.icns" || echo "warning: no icon"
for s in "${SCRIPTS[@]}"; do cp "$SRC/$s" "$RES/scripts/$s"; done
if   [ -d "$SRC/pylibs" ];  then cp -R "$SRC/pylibs"  "$RES/pylibs"
elif [ -d "$REPO/pylibs" ]; then cp -R "$REPO/pylibs" "$RES/pylibs"; fi

echo "==> relocatable python (aarch64) + $PY_LIBS"
if [ ! -s "$WORK/py.tar.gz" ]; then
  PB_URL="$(curl -fsSL https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
    | grep browser_download_url | grep "${PB_ARCH}-apple-darwin-install_only.tar.gz\"" | head -1 | cut -d'"' -f4)"
  [ -n "$PB_URL" ] || { echo "error: no python-build-standalone asset"; exit 1; }
  curl -fsSL "$PB_URL" -o "$WORK/py.tar.gz"
else
  echo "    (using cached py.tar.gz)"
fi
rm -rf "$WORK/python"; tar -xzf "$WORK/py.tar.gz" -C "$WORK"
cp -R "$WORK/python/." "$VENDOR/python/$VARCH/"
PYROOT="$VENDOR/python/$VARCH"
"$PYROOT/bin/python3" -m pip install --quiet --upgrade pip
"$PYROOT/bin/python3" -m pip install --quiet $PY_LIBS
echo "==> pruning python"
for d in test idlelib tkinter turtledemo lib2to3 ensurepip; do
  rm -rf "$PYROOT"/lib/python*/"$d"
done
rm -f "$PYROOT"/lib/python*/turtle.py
find "$PYROOT" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
find "$PYROOT" -type f -name '*.pyc' -delete 2>/dev/null || true
echo "    python now $(du -sh "$PYROOT" | cut -f1)"

echo "==> static arm64 ffmpeg + ffprobe"
FFT="$WORK/fftmp"; rm -rf "$FFT"; mkdir -p "$FFT"
( cd "$FFT" && npm init -y >/dev/null 2>&1 && npm i ffmpeg-ffprobe-static --no-save --no-audit --no-fund >/dev/null 2>&1 )
for t in ffmpeg ffprobe; do
  f="$(find "$FFT/node_modules/ffmpeg-ffprobe-static" -maxdepth 2 -type f -name "$t" 2>/dev/null | head -1 || true)"
  [ -n "$f" ] && { cp "$f" "$VENDOR/bin/$VARCH/$t"; chmod +x "$VENDOR/bin/$VARCH/$t"; } \
    || echo "  !! $t not fetched — drop an arm64 static build into $VENDOR/bin/$VARCH/"
done

if [ -n "$DEV_ID" ]; then
  echo "==> signing (Developer ID, hardened runtime)"
  find "$RES" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) -print0 \
    | while IFS= read -r -d '' f; do codesign --force --timestamp --options runtime --sign "$DEV_ID" "$f" 2>/dev/null || true; done
  codesign --force --deep --timestamp --options runtime --entitlements MusicTools.entitlements --sign "$DEV_ID" "$APP"
else
  echo "==> ad-hoc signing"; codesign --force --deep --sign - "$APP"
fi
du -sh "$APP"; echo "Built $APP  (arm64, self-contained, no Node)"
