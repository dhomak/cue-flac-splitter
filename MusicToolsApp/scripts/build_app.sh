#!/bin/bash
# Builds MusicTools.app (native WKWebView shell around your Node/Express server).
#
#   ./scripts/build_app.sh /path/to/your/music-tools   (dir containing server.js)
#
# Copies ONLY what the app runs — not node_modules/venv/vendor from your repo —
# then installs production node deps (express) and a slim Python venv.
# Uses your SYSTEM node + Homebrew ffmpeg at runtime (beta). See README to bundle them.

set -euo pipefail

APP_NAME="MusicTools"
SERVER_SRC="${1:?Usage: build_app.sh /path/to/your/music-tools (the dir containing server.js)}"
# App icon (override with ICON_SRC=... if it moves)
ICON_SRC="${ICON_SRC:-/Users/aalien/sandbox/split-cue/build/icon.icns}"
[ -f "$SERVER_SRC/server.js" ] || { echo "error: server.js not found in $SERVER_SRC" >&2; exit 1; }

# --- 1. Compile the Swift wrapper ---------------------------------------
echo "==> swift build (release)"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

# --- 2. Lay out the .app bundle -----------------------------------------
APP="build/$APP_NAME.app"
DEST="$APP/Contents/Resources/server"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$DEST"
cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist  "$APP/Contents/Info.plist"

# App icon
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
    echo "    icon: $ICON_SRC"
else
    echo "warning: icon not found at $ICON_SRC — building without a custom icon" >&2
fi

# --- 3. Copy ONLY the app's own files -----------------------------------
# Crucially excludes node_modules (which holds ~250MB of Electron!), the repo's
# venv, and vendor/. We rebuild the slim runtime deps below.
echo "==> copying server (excluding node_modules / venv / vendor / build)"
rsync -a \
    --exclude 'node_modules' \
    --exclude 'venv' \
    --exclude 'vendor' \
    --exclude 'build' \
    --exclude 'dist' \
    --exclude '.git' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '*.log' \
    --exclude '.DS_Store' \
    "$SERVER_SRC"/ "$DEST"/

# --- 4. Production node deps only (express; skips electron/dev) ----------
echo "==> installing production node deps"
( cd "$DEST" && { npm ci --omit=dev 2>/dev/null || npm install --omit=dev --no-audit --no-fund; } )

# --- 5. Slim Python venv (just what the scripts import) -----------------
echo "==> building slim python venv (mutagen, requests, charset-normalizer)"
python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install --quiet --upgrade pip
"$DEST/venv/bin/pip" install --quiet mutagen requests charset-normalizer

# --- 6. Ad-hoc sign so it launches locally ------------------------------
echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APP"

echo ""
echo "Built $APP"
du -sh "$APP"
echo "Run:  open \"$APP\"   (first launch: right-click -> Open)"
