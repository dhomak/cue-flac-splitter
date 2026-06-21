# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains audio processing utilities for FLAC/CUE file handling, primarily focused on:
- Splitting single-file FLAC albums using CUE sheets
- Converting FLAC files to CD-quality (44.1kHz/16-bit)
- Fetching lyrics for audio files
- Converting CUE file encodings

All scripts are designed for macOS with Unicode/NFD filename support.

## Core Scripts

### split-cue-unicode.pl
Main Perl script for splitting FLAC+CUE albums into individual tracks.

**Usage:**
```bash
./split-cue-unicode.pl [--delete] [--dry-run] [--to-root] [--overwrite-final] [ROOT]
```

**Key flags:**
- `--delete`: Remove .flac and .cue after successful split
- `--dry-run`: Preview changes without executing
- `--to-root`: Place final files in album directory (default: ./split/)
- `--overwrite-final`: Overwrite existing files when moving

**Architecture notes:**
- Uses ffmpeg/ffprobe for audio processing
- Handles multiple encodings (UTF-8, cp1251, latin1) for CUE files
- macOS NFD normalization for filesystem compatibility
- Stages files in temporary directory (.split.tmp-<pid>) when using --to-root, then atomically moves them
- Only deletes originals if ALL tracks succeed (planned_n == succeeded_n)
- Default: re-encodes FLAC at compression level 8 ($REENCODE=1)

**CUE parsing:**
- Extracts PERFORMER, TITLE, FILE, TRACK, INDEX entries
- Supports REM fields (DATE, GENRE)
- Uses INDEX 01 for track start (falls back to INDEX 00)
- Calculates track duration from next track's INDEX or total file duration

### flac_downsampler.sh
Converts FLAC files to CD-quality format with high-quality resampling.

**Usage:**
```bash
./flac_downsampler.sh [input_directory] [output_directory]
```

**Defaults:**
- Input: current directory
- Output: ./downsampled/

**Technical details:**
- Uses SoXR resampler (precision=28, Chebyshev filter)
- Target: 44.1kHz, 16-bit signed
- FLAC compression level 8
- Flattens directory structure (all files go to single output directory)

### flac_to_cd.sh
Recursive FLAC converter with directory structure preservation.

**Usage:**
```bash
./flac_to_cd.sh INPUT_DIR OUTPUT_DIR
```

**Features:**
- Preserves directory structure in output
- Skips already-converted files (16-bit/44.1kHz)
- Timestamp preservation (touch -r)
- Prevents OUTDIR inside INDIR
- Handles symlinks and whitespace via file_realpath()

**Debug mode:**
```bash
DEBUG=1 ./flac_to_cd.sh INPUT_DIR OUTPUT_DIR
```

### audio_lyrics_fetcher.py
Fetches lyrics for FLAC, MP3, and M4A/ALAC files.

**Usage:**
```bash
python3 audio_lyrics_fetcher.py <directory>
```

**Requirements:**
```bash
pip install mutagen requests
```

**API sources (priority order):**
1. LRCLIB (lrclib.net)
2. ChartLyrics
3. lyrics.ovh

**Behavior:**
- Skips files with existing .txt lyrics
- Extracts artist/title from file metadata
- 2-second delay between API requests
- Saves lyrics as .txt files alongside audio files

### cue_converter.sh
Converts CUE files from WINDOWS-1251 to UTF-8.

**Usage:**
```bash
./cue_converter.sh [directory]
```

**Operations:**
- Converts WINDOWS-1251 → UTF-8
- Removes carriage returns (\r)
- Strips BOM (Byte Order Mark)

## Dependencies

**Required:**
- ffmpeg (with SoXR support for flac_downsampler.sh)
- ffprobe
- perl (for split-cue-unicode.pl)
- iconv (for cue_converter.sh)
- Python 3 with mutagen + requests (for audio_lyrics_fetcher.py)

**Installation (macOS):**
```bash
brew install ffmpeg perl python3
pip3 install mutagen requests
```

## File Organization

**Default behavior:**
- `split-cue-unicode.pl`: Creates ./split/ subdirectory (unless --to-root)
- `flac_downsampler.sh`: Creates ./downsampled/
- `flac_to_cd.sh`: Uses specified OUTPUT_DIR
- `audio_lyrics_fetcher.py`: Writes .txt files alongside audio files

**Ignored directories:**
- split/ (output directory)
- venv/ (Python virtual environment)
- __pycache__/

## Common Workflows

**Split album and place tracks in root directory:**
```bash
./split-cue-unicode.pl --to-root /path/to/album
```

**Split and clean up originals:**
```bash
# Preview first
./split-cue-unicode.pl --to-root --delete --dry-run /path/to/album
# Execute
./split-cue-unicode.pl --to-root --delete /path/to/album
```

**Downsample high-res FLAC to CD quality:**
```bash
./flac_downsampler.sh /path/to/hires /path/to/output
```

**Convert entire music library preserving structure:**
```bash
./flac_to_cd.sh /Volumes/Music/FLAC /Volumes/Music/CD_Quality
```

**Fetch lyrics for album:**
```bash
python3 audio_lyrics_fetcher.py /path/to/album
```

## Unicode and macOS Considerations

- All scripts handle UTF-8, including macOS NFD (decomposed) filenames
- `split-cue-unicode.pl` includes os_norm() and os_encode() helpers for macOS compatibility
- CUE files may be in various encodings (UTF-8, cp1251, latin1) - the Perl script auto-detects
- Use `cue_converter.sh` to normalize CUE files to UTF-8 before processing
