#!/usr/bin/env python3
"""
Encoding Fixer
Repairs legacy-encoding mojibake (typically Windows-1251 Cyrillic) in:
  * sidecar text files  -> .cue .txt .log .nfo .m3u  (re-saved as UTF-8)
  * MP3 ID3 tags        -> cp1251 bytes stored in Latin-1 frames (mid3iconv case)

SAFE BY DEFAULT: runs as a dry-run and only previews changes. Pass --apply
to actually modify files. The MP3 fix is confidence-gated so correctly-stored
Latin tags (e.g. "Björk") are not corrupted into Cyrillic.

Usage:
    python3 encoding_fixer.py <directory> [--apply] [--backup]
                              [-w WORKERS] [--source-encoding cp1251]
                              [--threshold 0.6] [--no-detect] [--verbose]
"""

import os
import sys
import shutil
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

from mutagen.mp3 import MP3
from mutagen.id3 import ID3, ID3NoHeaderError, TextFrame, COMM

try:
    from charset_normalizer import from_bytes
    DETECT_AVAILABLE = True
except ImportError:
    DETECT_AVAILABLE = False

TEXT_EXTS = {'.cue', '.txt', '.log', '.nfo', '.m3u'}
MP3_EXTS = {'.mp3'}
CYRILLIC = ('\u0400', '\u04FF')  # inclusive range


def clip(s, n=58):
    """One-line, length-capped preview of a string."""
    s = s.replace('\r', ' ').replace('\n', ' ⏎ ')
    return s if len(s) <= n else s[:n - 1] + '…'


def cyrillic_fraction(text):
    alpha = [c for c in text if c.isalpha()]
    if not alpha:
        return 0.0
    cyr = sum(1 for c in alpha if CYRILLIC[0] <= c <= CYRILLIC[1])
    return cyr / len(alpha)


def recover_mojibake(text, source_encoding, threshold):
    """If `text` looks like `source_encoding` bytes misread as Latin-1,
    return the recovered string; otherwise None.

    The guard chain:
      - encode back to latin-1 -> only works if every char <= 0xFF.
        Real Unicode (e.g. proper Cyrillic) has chars > 0xFF and fails here,
        so already-correct text is left alone.
      - decode as the legacy encoding -> recovers the intended bytes.
      - require the result to be mostly Cyrillic -> rejects false positives
        like a correctly-stored "Björk" -> "Bjцrk".
    """
    if not isinstance(text, str) or not text:
        return None
    try:
        raw = text.encode('latin-1')
    except UnicodeEncodeError:
        return None  # already real Unicode — don't touch
    try:
        fixed = raw.decode(source_encoding)
    except (UnicodeDecodeError, LookupError):
        return None
    if fixed == text:
        return None  # pure ASCII, nothing to do
    if cyrillic_fraction(fixed) < threshold:
        return None  # not confidently Cyrillic — leave it
    return fixed


# ---------------------------------------------------------------------------
# Per-file fixers. Each returns (outcome, n_changes, log_lines).
# outcome in {'fixed', 'clean', 'error'}.  In dry-run, 'fixed' == 'would fix'.
# ---------------------------------------------------------------------------
class Fixer:
    def __init__(self, source_encoding='cp1251', threshold=0.6,
                 detect=True, apply=False, backup=False, verbose=False):
        self.source_encoding = source_encoding
        self.threshold = threshold
        self.detect = detect and DETECT_AVAILABLE
        self.apply = apply
        self.backup = backup
        self.verbose = verbose

    def _backup(self, path):
        if self.backup:
            shutil.copy2(path, str(path) + '.bak')

    # -- text / cue --------------------------------------------------------
    def fix_text(self, path):
        logs = []
        emit = logs.append
        try:
            raw = path.read_bytes()
        except Exception as e:
            emit(f"🔤 {path.name}\n  ⚠️  Read error: {type(e).__name__}")
            return ('error', 0, logs)

        if not raw.strip():
            return ('clean', 0, [])

        # Already valid UTF-8 (ASCII included) -> nothing to do.
        try:
            raw.decode('utf-8')
            if self.verbose:
                emit(f"🔤 {path.name}\n  ✓ already UTF-8")
            return ('clean', 0, logs if self.verbose else [])
        except UnicodeDecodeError:
            pass

        # Decode with detected or forced legacy encoding.
        enc = self.source_encoding
        if self.detect:
            match = from_bytes(raw).best()
            if match is None:
                emit(f"🔤 {path.name}\n  ⚠️  Could not detect encoding")
                return ('error', 0, logs)
            enc = match.encoding
            text = str(match)
        else:
            try:
                text = raw.decode(enc)
            except (UnicodeDecodeError, LookupError) as e:
                emit(f"🔤 {path.name}\n  ⚠️  Decode as {enc} failed: {type(e).__name__}")
                return ('error', 0, logs)

        emit(f"🔤 {path.name}")
        emit(f"  {enc} → utf-8")
        sample = next((ln for ln in text.splitlines()
                       if any(ord(c) > 127 for c in ln)), '')
        if sample:
            emit(f"  preview: {clip(sample.strip())}")

        if self.apply:
            try:
                self._backup(path)
                path.write_bytes(text.encode('utf-8'))
                emit("  ✓ converted")
            except Exception as e:
                emit(f"  ⚠️  Write error: {type(e).__name__}")
                return ('error', 0, logs)
        return ('fixed', 1, logs)

    # -- mp3 id3 -----------------------------------------------------------
    def fix_mp3(self, path):
        logs = []
        emit = logs.append
        try:
            audio = MP3(str(path))
            tags = audio.tags
        except Exception as e:
            emit(f"🎵 {path.name}\n  ⚠️  Read error: {type(e).__name__}")
            return ('error', 0, logs)

        if not tags:
            return ('clean', 0, [])

        changes = []  # (frame_name, old, new)
        for frame in list(tags.values()):
            if not isinstance(frame, (TextFrame, COMM)):
                continue
            new_texts, changed = [], False
            for item in frame.text:
                fixed = recover_mojibake(item, self.source_encoding, self.threshold)
                if fixed is not None:
                    changes.append((frame.FrameID, item, fixed))
                    new_texts.append(fixed)
                    changed = True
                else:
                    new_texts.append(item)
            if changed:
                frame.text = new_texts
                frame.encoding = 3  # store as UTF-8 going forward

        if not changes:
            if self.verbose:
                emit(f"🎵 {path.name}\n  ✓ tags clean")
            return ('clean', 0, logs if self.verbose else [])

        emit(f"🎵 {path.name}")
        for name, old, new in changes:
            emit(f"  ✎ {name}: \"{clip(old)}\" → \"{clip(new)}\"")

        if self.apply:
            try:
                self._backup(path)
                tags.save(str(path), v2_version=4)
                emit("  ✓ tags rewritten (ID3v2.4 / UTF-8)")
            except Exception as e:
                emit(f"  ⚠️  Save error: {type(e).__name__}")
                return ('error', 0, logs)
        return ('fixed', len(changes), logs)

    # -- dispatch ----------------------------------------------------------
    def process_one(self, path):
        ext = path.suffix.lower()
        if ext in MP3_EXTS:
            return self.fix_mp3(path)
        if ext in TEXT_EXTS:
            return self.fix_text(path)
        return ('clean', 0, [])


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
def find_files(root):
    wanted = TEXT_EXTS | MP3_EXTS
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            if os.path.splitext(name)[1].lower() in wanted:
                files.append(Path(dirpath) / name)
    return sorted(files)


def run(directory, fixer, workers):
    root = Path(directory).expanduser().resolve()
    if not root.exists():
        print(f"❌ Error: Directory '{root}' does not exist", flush=True)
        return

    mode = "APPLY (writing changes)" if fixer.apply else "DRY RUN (preview only)"
    print(f"🔍 Scanning: {root}", flush=True)
    print(f"⚙️  Mode: {mode}  |  legacy encoding: {fixer.source_encoding}"
          f"  |  detect: {'on' if fixer.detect else 'off'}", flush=True)
    if fixer.apply and fixer.backup:
        print("🛟  Backups: .bak copies will be written", flush=True)
    if not DETECT_AVAILABLE and fixer.detect:
        print("⚠️  charset_normalizer not available — text detection disabled",
              flush=True)

    files = find_files(root)
    if not files:
        print("❌ No .cue/.txt/.log/.nfo/.m3u or .mp3 files found", flush=True)
        return

    print(f"📁 Found {len(files)} candidate files\n", flush=True)
    print("=" * 60, flush=True)

    counts = {'fixed': 0, 'clean': 0, 'error': 0}
    total_changes = 0

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(fixer.process_one, p): p for p in files}
        for fut in as_completed(futures):
            try:
                outcome, n, logs = fut.result()
            except Exception as e:
                print(f"\n⚠️  {futures[fut].name}: {type(e).__name__}: {e}", flush=True)
                counts['error'] += 1
                continue
            counts[outcome] = counts.get(outcome, 0) + 1
            total_changes += n
            if logs:
                print("\n" + "\n".join(logs), flush=True)

    print("\n" + "=" * 60, flush=True)
    print("📊 Summary:", flush=True)
    print(f"  Files scanned:    {sum(counts.values())}", flush=True)
    verb = "fixed" if fixer.apply else "to fix"
    print(f"  Files {verb}:    {counts['fixed']} ({total_changes} changes)", flush=True)
    print(f"  Already clean:    {counts['clean']}", flush=True)
    print(f"  Errors:           {counts['error']}", flush=True)
    if not fixer.apply and counts['fixed']:
        print("\n💡 Dry run — nothing was modified. "
              "Re-run with --apply to write these changes.", flush=True)


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    ap = argparse.ArgumentParser(
        description="Fix Windows-1251 (or other) mojibake in CUE/text files and MP3 tags."
    )
    ap.add_argument('directory', help='Root directory to scan recursively')
    ap.add_argument('--apply', action='store_true',
                    help='Actually write changes (default is dry-run preview)')
    ap.add_argument('--backup', action='store_true',
                    help='Write .bak copies before modifying (only with --apply)')
    ap.add_argument('-w', '--workers', type=int, default=8,
                    help='Concurrent workers (default: 8)')
    ap.add_argument('--source-encoding', default='cp1251',
                    help='Legacy encoding to recover from (default: cp1251)')
    ap.add_argument('--threshold', type=float, default=0.6,
                    help='Min Cyrillic fraction to accept an MP3 tag fix (default: 0.6)')
    ap.add_argument('--no-detect', action='store_true',
                    help='Disable auto-detection for text files; force --source-encoding')
    ap.add_argument('--verbose', action='store_true',
                    help='Also log files that need no changes')
    args = ap.parse_args()

    print("🔤 Encoding Fixer\n", flush=True)
    fixer = Fixer(
        source_encoding=args.source_encoding,
        threshold=args.threshold,
        detect=not args.no_detect,
        apply=args.apply,
        backup=args.backup,
        verbose=args.verbose,
    )
    run(args.directory, fixer, max(1, args.workers))


if __name__ == "__main__":
    main()
