# CLAUDE.md - AI Assistant Guide for cue-flac-splitter

## Repository Overview

**Purpose**: Audio processing toolkit for high-quality FLAC files, CUE sheet splitting, format conversion, and lyrics fetching.

**Primary Use Cases**:
- Split single-file CUE+FLAC albums into individual tracks
- Downsample high-resolution FLAC to CD quality (44.1kHz/16-bit)
- Fetch and save lyrics for audio files from multiple online sources

**Target Platform**: Primarily macOS (with Unicode NFD normalization), but works on Linux

---

## Codebase Structure

```
cue-flac-splitter/
├── split-cue-unicode.pl      # Main CUE splitting script (Perl)
├── flac_downsampler.sh        # FLAC downsampler (Bash)
├── flac_to_cd.sh             # Recursive FLAC converter (Bash)
├── audio_lyrics_fetcher.py   # Lyrics fetcher (Python 3)
├── .gitignore                # Git ignore rules
└── README.md                 # Basic project information
```

### File Overview

#### 1. `split-cue-unicode.pl` (394 lines)
**Purpose**: Unicode-safe CUE+FLAC album splitter using ffmpeg

**Key Features**:
- Parses CUE sheets with multiple encodings (UTF-8, cp1251, latin1)
- Handles Unicode properly on macOS (NFD) and Linux (NFC)
- Splits single FLAC files into individual tracks
- Preserves metadata (artist, title, album, date, genre, track number)
- Re-encodes to FLAC with compression level 8 (configurable)
- Supports atomic operations with staging directories

**CLI Flags**:
- `--delete`: Delete original .flac and .cue after successful split
- `--dry-run`: Preview operations without making changes
- `--to-root`: Place split files in album directory (not subdirectory)
- `--overwrite-final`: Overwrite existing files instead of renaming

**Dependencies**: `ffmpeg`, `ffprobe`, `perl` (standard library only)

**Important Functions**:
- `parse_cue()` (line 128): Parses CUE sheet and extracts metadata
- `split_album_using_cue()` (line 170): Main splitting logic
- `os_norm()` / `os_encode()` (lines 50-51): Unicode normalization helpers
- `resolve_fs_path()` (line 85): Resolves filesystem paths with Unicode

#### 2. `flac_downsampler.sh` (195 lines)
**Purpose**: Downsample FLAC files to 44.1kHz/16-bit for CD compatibility

**Key Features**:
- Recursively finds FLAC files in directory tree
- Uses SoXR resampler for high-quality downsampling
- Flattens directory structure (all output files in single directory)
- Shows file size reduction statistics
- Colored console output for better UX
- Detects and displays original/final audio formats

**Usage**: `./flac_downsampler.sh [input_directory] [output_directory]`

**Dependencies**: `ffmpeg`, `Python 3` (for JSON parsing)

**FFmpeg Settings**:
- Sample rate: 44100 Hz
- Sample format: s16 (16-bit signed integer)
- Resampler: SoXR with precision=28, cheby=1
- Compression: level 8

#### 3. `flac_to_cd.sh` (113 lines)
**Purpose**: Recursively convert FLAC files to CD quality while preserving directory structure

**Key Features**:
- Maintains directory tree structure in output
- Skips already converted files (timestamp-based)
- Detects files already at 16/44.1 and skips them
- Robust path handling (symlinks, whitespace, special characters)
- Validates input/output directories don't overlap
- Preserves file timestamps

**Usage**: `./flac_to_cd.sh INPUT_DIR OUTPUT_DIR`

**Debug Mode**: `DEBUG=1 ./flac_to_cd.sh INPUT_DIR OUTPUT_DIR`

**Dependencies**: `ffmpeg`, `ffprobe`, `python3` (optional, for better path resolution)

**Path Handling**:
- Uses `file_realpath()` (line 36) for canonical paths
- Uses `rel_from_indir()` (line 55) for relative path calculation
- Python 3 preferred for path operations, falls back to `realpath`

#### 4. `audio_lyrics_fetcher.py` (288 lines)
**Purpose**: Fetch and save lyrics for FLAC, MP3, and M4A/ALAC files

**Key Features**:
- Multi-source lyrics fetching with fallback (LRCLIB → ChartLyrics → lyrics.ovh)
- Supports FLAC, MP3, M4A/ALAC formats
- Reads metadata from audio files to get artist/title
- Saves lyrics as .txt files alongside audio files
- Skips files that already have lyrics
- Rate limiting (2 second delay between requests)
- Progress tracking and statistics

**Usage**: Requires virtual environment
```bash
source venv/bin/activate
python3 audio_lyrics_fetcher.py <directory>
```

**Dependencies** (Python packages):
- `mutagen` - Audio metadata reading
- `requests` - HTTP requests for API calls

**API Sources** (in priority order):
1. LRCLIB (https://lrclib.net/api/search) - Primary, most reliable
2. ChartLyrics (http://api.chartlyrics.com/) - XML-based fallback
3. lyrics.ovh (https://api.lyrics.ovh/v1/) - JSON-based fallback

**Classes**:
- `LyricsFetcher` (line 18): Handles API requests to multiple sources
- `AudioParser` (line 143): Processes audio files and saves lyrics

---

## Development Workflows

### Working with CUE+FLAC Albums

**Typical workflow**:
1. Place CUE+FLAC album in a directory
2. Run split script: `./split-cue-unicode.pl --to-root /path/to/album`
3. Preview with: `./split-cue-unicode.pl --dry-run --delete /path`
4. Delete originals after verification: `./split-cue-unicode.pl --delete /path`

**Output locations**:
- Default: Files placed in `split/` subdirectory
- With `--to-root`: Files placed in album directory directly

### Converting High-Res FLAC to CD Quality

**Two scripts available**:

**Option 1**: `flac_downsampler.sh` (flattens structure)
```bash
./flac_downsampler.sh ~/Music/HighRes ~/Music/CD
```

**Option 2**: `flac_to_cd.sh` (preserves structure)
```bash
./flac_to_cd.sh ~/Music/HighRes ~/Music/CD
```

**When to use which**:
- Use `flac_downsampler.sh` when you want all files in one directory
- Use `flac_to_cd.sh` when preserving folder structure is important

### Fetching Lyrics

**Setup** (first time only):
```bash
python3 -m venv venv
source venv/bin/activate
pip install mutagen requests
```

**Running**:
```bash
source venv/bin/activate
python3 audio_lyrics_fetcher.py ~/Music/Album
```

**Output**: Creates `.txt` files alongside each audio file

---

## Key Technical Conventions

### Unicode Handling

**Critical for macOS compatibility**:
- macOS uses NFD (decomposed) Unicode normalization
- Linux uses NFC (composed) normalization
- The Perl script handles both via `os_norm()` function (line 50)

**Implementation**:
```perl
my $IS_DARWIN = ($^O eq 'darwin');
sub os_norm   { my ($s)=@_; return $IS_DARWIN ? NFD($s) : NFC($s) }
sub os_encode { my ($s)=@_; return encode('UTF-8', os_norm($s)) }
```

**Why this matters**:
- Files created on macOS may not match literal string comparisons on Linux
- The `resolve_fs_path()` function (line 85) handles case-insensitive matching

### Metadata Preservation

**CUE splitting preserves**:
- TITLE (track title)
- ARTIST (track artist, falls back to album artist)
- ALBUM (album title)
- ALBUM_ARTIST (album artist)
- DATE (from REM DATE in CUE)
- GENRE (from REM GENRE in CUE)
- TRACK (track number, zero-padded)

**FLAC conversion preserves**:
- All metadata using `-map_metadata 0` flag

### FFmpeg Best Practices

**For splitting** (split-cue-unicode.pl:245):
```bash
ffmpeg -ss START_TIME -i INPUT -t DURATION \
  -map_metadata -1 \  # Clear existing metadata
  [metadata flags]   \  # Set new metadata
  -c:a flac -compression_level 8 \
  OUTPUT
```

**For downsampling** (both conversion scripts):
```bash
ffmpeg -i INPUT \
  -ar 44100 \
  -sample_fmt s16 \
  -af "aresample=resampler=soxr:precision=28:cheby=1" \
  -compression_level 8 \
  OUTPUT
```

**Key settings**:
- `-ar 44100`: 44.1 kHz sample rate (CD quality)
- `-sample_fmt s16`: 16-bit signed integer (CD quality)
- `-compression_level 8`: Maximum FLAC compression (slower but smaller)
- `soxr` resampler: High-quality downsampling

### Error Handling Philosophy

**Perl script** (split-cue-unicode.pl):
- Uses `set -euo pipefail` equivalent via `or return` patterns
- Skips problematic files with `[SKIP]` messages
- Validates all inputs before processing
- Atomic operations: staging directory → final location

**Bash scripts**:
- `set -euo pipefail`: Exit on error, undefined vars, pipe failures
- Continue on per-file errors (don't abort entire batch)
- Validate dependencies at startup
- Write test to output directory before processing

**Python script**:
- Try multiple API sources before giving up
- Skip files with missing metadata
- Continue on errors, show summary at end
- Rate limiting to be respectful to APIs

### File Naming Conventions

**Track filenames** (split-cue-unicode.pl:236):
```perl
my $nn   = sprintf("%02d", $t->{num});    # Zero-padded track number
my $base = "$nn - $t_title";
$base =~ s/[\/\\:\*\?\"<>\|]/_/g;         # Sanitize illegal chars
```

**Format**: `01 - Track Title.flac`

**Character sanitization**:
- Replaces: `/` `\` `:` `*` `?` `"` `<` `>` `|`
- With: `_`

---

## Common Issues and Solutions

### Issue: "Required tool not found in PATH"

**Cause**: Missing dependencies

**Solution**:
```bash
# macOS
brew install ffmpeg perl

# Linux
sudo apt-get install ffmpeg perl  # Debian/Ubuntu
sudo yum install ffmpeg perl      # RHEL/CentOS
```

### Issue: Filename encoding problems on macOS

**Cause**: NFD vs NFC normalization mismatch

**Solution**: Already handled by `os_norm()` function in Perl script. If you encounter issues:
- Ensure `use Unicode::Normalize qw/NFC NFD/;` is present
- Use `os_encode()` wrapper for all filesystem operations

### Issue: "ERROR: OUTDIR inside INDIR" in flac_to_cd.sh

**Cause**: Output directory is inside input directory (would cause infinite loop)

**Solution**: Use separate output directory
```bash
# Wrong
./flac_to_cd.sh /music /music/converted

# Right
./flac_to_cd.sh /music /converted
```

### Issue: Python script can't find audio files

**Cause**: Not activating virtual environment

**Solution**:
```bash
source venv/bin/activate
python3 audio_lyrics_fetcher.py <directory>
```

### Issue: Split files are huge (larger than CD quality)

**Cause**: Original FLAC is high-resolution (96kHz/24-bit or higher)

**Solution**: Use one of the conversion scripts first:
```bash
./flac_to_cd.sh /path/to/highres /path/to/cd
./split-cue-unicode.pl /path/to/cd
```

---

## Testing Approach

### Manual Testing Checklist

**For CUE splitting**:
- [ ] Test with UTF-8 encoded CUE sheet
- [ ] Test with cp1251 encoded CUE sheet (Cyrillic)
- [ ] Test with filenames containing spaces
- [ ] Test with Unicode characters in track titles
- [ ] Test `--dry-run` flag
- [ ] Test `--to-root` flag
- [ ] Test `--delete` flag
- [ ] Verify all tracks created (count matches CUE)
- [ ] Verify metadata preserved
- [ ] Verify file sizes > 0

**For FLAC conversion**:
- [ ] Test with high-res FLAC (96kHz/24-bit)
- [ ] Test with already-CD-quality FLAC
- [ ] Test with nested directory structure
- [ ] Verify output is 44.1kHz/16-bit
- [ ] Verify metadata preserved
- [ ] Test skip logic (re-run on same files)

**For lyrics fetching**:
- [ ] Test with FLAC files
- [ ] Test with MP3 files
- [ ] Test with M4A files
- [ ] Test with missing metadata
- [ ] Test with existing .txt files (should skip)
- [ ] Verify API fallback works
- [ ] Check rate limiting behavior

---

## Git Conventions

### Branch Naming
- Feature branches: `feature/description`
- Bug fixes: `fix/description`
- Claude AI branches: `claude/claude-md-*` (auto-generated)

### Commit Message Style
Based on recent commits:
- Use imperative mood: "add", "update", "fix" (not "added", "updated")
- Be concise but descriptive
- Examples from history:
  - `Update README.md`
  - `update .gitignore`
  - `add universal lyrics fetcher because why not`
  - `added new flac downsampler script, more advanced`

### Gitignore Rules
```
.DS_Store
*.DS_Store
split/          # Output from CUE splitter
venv/           # Python virtual environment
__pycache__/    # Python bytecode
*.pyc
```

---

## AI Assistant Guidelines

### When Adding New Features

1. **Maintain the existing style**:
   - Perl: Use `strict`, `warnings`, `utf8` pragmas
   - Bash: Use `set -euo pipefail`
   - Python: Use type hints where beneficial, follow PEP 8

2. **Preserve Unicode handling**:
   - Always use `os_encode()` for filesystem operations in Perl
   - Test on both macOS (NFD) and Linux (NFC)

3. **Keep dependencies minimal**:
   - Perl: Standard library only (no CPAN)
   - Bash: Standard tools (ffmpeg, ffprobe, find, etc.)
   - Python: Only add packages if absolutely necessary

4. **Maintain error handling patterns**:
   - Don't abort entire batch on single file failure
   - Print clear status messages with prefixes: `[INFO]`, `[ERR]`, `[SKIP]`
   - Validate inputs before processing

### When Debugging

**Check these first**:
1. Dependencies installed? (`which ffmpeg ffprobe perl python3`)
2. File permissions correct? (`ls -la`, check execute bits)
3. Virtual environment activated? (for Python script)
4. Paths using correct normalization? (macOS vs Linux)
5. Encoding issues? (UTF-8 vs cp1251 vs latin1)

**Enable debug mode**:
- Perl: Add `say` statements to trace execution
- Bash: Use `DEBUG=1 ./script.sh` for verbose output
- Python: Check exception messages, add print statements

### When Modifying Scripts

**Critical sections to preserve**:
1. Unicode normalization logic (split-cue-unicode.pl:50-101)
2. CUE parsing (split-cue-unicode.pl:128-165)
3. Path resolution (flac_to_cd.sh:36-70)
4. Metadata extraction (audio_lyrics_fetcher.py:159-189)

**Safe to modify**:
- Output formatting (colors, messages)
- Compression levels
- API endpoints (add new sources)
- CLI flag handling (add new options)

### When Reviewing Code

**Look for**:
- Unicode handling issues
- Missing error checks
- Hardcoded paths
- Unsafe `eval` or `system` calls
- API rate limiting violations
- Memory leaks in long-running operations

---

## Performance Considerations

### CUE Splitting
- **Bottleneck**: FFmpeg encoding
- **Optimization**: Set `$REENCODE = 0` for copy mode (much faster, but no re-compression)
- **Typical speed**: ~5-10 seconds per track (with re-encoding)

### FLAC Conversion
- **Bottleneck**: Resampling algorithm
- **Optimization**: Lower compression level (8 → 5) for faster encoding
- **Typical speed**: 2-5x realtime (96kHz/24bit → 44.1kHz/16bit)

### Lyrics Fetching
- **Bottleneck**: Network requests
- **Optimization**: Adjust delay in AudioParser (line 283) - but don't abuse APIs
- **Typical speed**: 2-3 seconds per track (2s delay + API call)

**Parallel processing note**: None of these scripts currently support parallel processing. This could be added but would require careful handling of Unicode paths and shell escaping.

---

## External Resources

### Dependencies Documentation
- FFmpeg: https://ffmpeg.org/documentation.html
- Mutagen: https://mutagen.readthedocs.io/
- Perl Unicode: https://perldoc.perl.org/perlunitut

### Audio Format Specifications
- FLAC: https://xiph.org/flac/format.html
- CUE Sheet: https://en.wikipedia.org/wiki/Cue_sheet_(computing)
- CD Audio: 44.1 kHz, 16-bit PCM

### API Documentation
- LRCLIB: https://lrclib.net/docs
- ChartLyrics: http://api.chartlyrics.com/
- lyrics.ovh: https://lyricsovh.docs.apiary.io/

---

## Version History Context

Based on recent commits:
- Latest features include universal lyrics fetcher
- Recent focus on FLAC downsampling improvements
- Added `--to-root` argument for flexible output placement
- Improved .gitignore to exclude generated files

---

## Questions to Ask Before Making Changes

1. **Does this change affect Unicode handling?**
   - If yes, test on both macOS and Linux

2. **Does this add new dependencies?**
   - If yes, document in README and this file
   - Prefer standard library solutions

3. **Does this change metadata handling?**
   - If yes, verify with `ffprobe` that tags are preserved

4. **Does this add new CLI flags?**
   - If yes, update usage documentation in script POD/comments

5. **Does this change error handling?**
   - If yes, ensure it's consistent with existing patterns

6. **Will this work with large libraries (10,000+ files)?**
   - If unsure, test performance and memory usage

---

## Summary for AI Assistants

**When you interact with this codebase**:
- This is a mature, working toolkit - avoid unnecessary refactoring
- Unicode handling is critical - never simplify it without testing
- The scripts are meant to be standalone - avoid adding framework dependencies
- Error messages should be clear and actionable
- Changes should be backward compatible with existing workflows
- Test with real audio files before committing

**Primary maintainer concerns**:
- Correctness (don't corrupt audio or metadata)
- Unicode compatibility (especially macOS NFD)
- Minimal dependencies (easy to deploy)
- Clear error messages (easy to debug)

**This codebase values**:
- Reliability over features
- Clarity over cleverness
- Compatibility over optimization
