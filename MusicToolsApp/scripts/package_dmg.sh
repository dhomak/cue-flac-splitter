#!/bin/bash
# Packages build/MusicTools.app into a distributable DMG (drag-to-Applications).
#
#   ./scripts/package_dmg.sh
#
# Optional:
#   DEV_ID="Developer ID Application: Name (TEAMID)"   -> signs the DMG
#   NOTARY_PROFILE=musictools-profile                  -> notarizes + staples the DMG
#   BG_SRC=/path/to/dmg_bg.png                        -> custom background (default: build/icon_1024.png area)
#
# Run after build_dist.sh, on macOS. Requires create-dmg (brew install create-dmg).
set -euo pipefail

APP_NAME="MusicTools"
VOL_NAME="Music Tools"
REPO_ROOT="$(cd "$(dirname "$0")/../.."; pwd)"
WORK="$(pwd)/build"
APP="$WORK/$APP_NAME.app"
DMG="$WORK/$APP_NAME.dmg"
DEV_ID="${DEV_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
BG_SRC="${BG_SRC:-$REPO_ROOT/build/dmg_bg.png}"
BG_SCRIPT="$REPO_ROOT/build/make_dmg_bg.py"

[ -d "$APP" ] || { echo "error: $APP not found — run build_dist.sh first" >&2; exit 1; }

# Generate background if missing
if [ ! -f "$BG_SRC" ] && [ -f "$BG_SCRIPT" ]; then
  echo "==> generating DMG background"
  python3 "$BG_SCRIPT"
fi

rm -rf "$DMG"

echo "==> creating DMG"
if command -v create-dmg >/dev/null 2>&1 && [ -f "$BG_SRC" ]; then
  # Fancy themed DMG
  # Window: 660x400 logical. Icons at logical (160,280) and (500,280).
  create-dmg \
    --volname "$VOL_NAME" \
    --volicon "$REPO_ROOT/build/icon.icns" \
    --background "$BG_SRC" \
    --window-pos 200 150 \
    --window-size 660 400 \
    --icon-size 100 \
    --text-size 11 \
    --icon "$APP_NAME.app" 160 280 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 500 280 \
    "$DMG" \
    "$APP" 2>&1 | grep -v "^$"
else
  # Fallback: plain hdiutil
  echo "  (create-dmg not found or no background — using plain hdiutil)"
  STAGE="$WORK/dmg-stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
  rm -rf "$STAGE"
fi

# Sign the DMG itself (optional)
if [ -n "$DEV_ID" ]; then
  echo "==> signing DMG"
  codesign --force --sign "$DEV_ID" "$DMG"
fi

# Notarize + staple the DMG (optional; needs a stored notarytool profile)
if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> notarizing DMG (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo ""
ls -lh "$DMG"
echo "Built $DMG"
