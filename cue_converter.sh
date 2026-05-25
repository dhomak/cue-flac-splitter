#!/bin/bash

# Script to convert .cue files from WINDOWS-1251 to UTF-8
# Removes carriage returns and BOM (Byte Order Mark)
# Usage: ./convert_cue.sh [directory]

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counter for processed files
count=0

# Get directory from argument or use current directory
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

echo "Searching for .cue files..."

# Find all .cue files and process them
find "$TARGET_DIR" -type f -name "*.cue" -print0 | while IFS= read -r -d '' f; do
    echo -e "${YELLOW}Processing:${NC} $f"
    
    # Convert encoding, remove carriage returns and BOM
    if iconv -f WINDOWS-1251 -t UTF-8 "$f" \
       | perl -pe 's/\r$//' \
       | perl -pe 's/^\x{FEFF}//' > "$f.tmp"; then
        
        # Replace original file with converted one
        mv "$f.tmp" "$f"
        echo -e "${GREEN}✓ Converted:${NC} $f"
        ((count++))
    else
        echo -e "${RED}✗ Failed:${NC} $f"
        # Clean up temp file if it exists
        rm -f "$f.tmp"
    fi
    echo ""
done

echo -e "${GREEN}Done! Processed $count file(s).${NC}"