#!/bin/bash

# Script to convert .cue files to UTF-8
# Auto-detects encoding, skips already-UTF-8 files
# Usage: ./cue_converter.sh [directory]

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

count=0
skipped=0
failed=0

if [ $# -eq 0 ]; then
    TARGET_DIR="."
    echo -e "${BLUE}No directory specified, using current directory${NC}"
else
    TARGET_DIR="$1"
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${RED}Error: Directory '$TARGET_DIR' does not exist${NC}"
        exit 1
    fi
    echo -e "${BLUE}Target directory: $TARGET_DIR${NC}"
fi

# Check dependencies
for cmd in iconv file uchardet; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Missing dependency: $cmd${NC}"
        echo "Install with: brew install uchardet (or apt install uchardet)"
        exit 1
    fi
done

echo "Searching for .cue files..."
echo ""

find "$TARGET_DIR" -type f -name "*.cue" -print0 | while IFS= read -r -d '' f; do
    echo -e "${YELLOW}Processing:${NC} $f"

    # Detect encoding
    detected=$(uchardet "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    echo -e "  Detected encoding: ${CYAN}$detected${NC}"

    # Skip if already UTF-8 (and not ASCII which is UTF-8 compatible)
    if [[ "$detected" == "utf-8" || "$detected" == "ascii" ]]; then
        echo -e "  ${GREEN}✓ Already UTF-8, skipping${NC}"
        ((skipped++))
        echo ""
        continue
    fi

    # Map detected encoding to iconv-compatible name
    case "$detected" in
        windows-1251|cp1251) FROM_ENC="WINDOWS-1251" ;;
        koi8-r)               FROM_ENC="KOI8-R" ;;
        iso-8859-5)           FROM_ENC="ISO-8859-5" ;;
        *)                    FROM_ENC=$(echo "$detected" | tr '[:lower:]' '[:upper:]') ;;
    esac

    echo -e "  Converting from: ${CYAN}$FROM_ENC${NC}"

    if iconv -f "$FROM_ENC" -t UTF-8 "$f" \
       | perl -pe 's/\r$//' \
       | perl -pe 's/^\x{FEFF}//' > "$f.tmp"; then
        mv "$f.tmp" "$f"
        echo -e "  ${GREEN}✓ Converted successfully${NC}"
        ((count++))
    else
        echo -e "  ${RED}✗ Failed to convert${NC}"
        rm -f "$f.tmp"
        ((failed++))
    fi
    echo ""
done

echo -e "${GREEN}Done!${NC} Converted: $count | Skipped (already UTF-8): $skipped | Failed: $failed"