#!/usr/bin/env python3
"""
Audio Lyrics Fetcher
Recursively finds FLAC, ALAC (M4A), and MP3 files and fetches lyrics
from LRCLIB -> ChartLyrics -> lyrics.ovh. Synced lyrics are saved as
.lrc, plain lyrics as .txt, alongside each audio file.

Optimized: single directory walk, concurrent fetching, automatic
retries with backoff, thread-local HTTP sessions.

Usage:
    python3 audio_lyrics_fetcher.py <directory> [-w WORKERS] [-d DELAY] [--overwrite]
"""

import argparse
import os
import sys
import time
import threading
from pathlib import Path
from urllib.parse import quote
from concurrent.futures import ThreadPoolExecutor, as_completed
import xml.etree.ElementTree as ET

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from mutagen.flac import FLAC
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4

AUDIO_EXTS = {'.flac', '.mp3', '.m4a', '.mp4'}
USER_AGENT = 'music-tools-lyrics-fetcher/2.0'

# ---------------------------------------------------------------------------
# HTTP session (thread-local so the retry-enabled session isn't shared across
# worker threads, which requests.Session does not officially support)
# ---------------------------------------------------------------------------
_local = threading.local()


def _build_retry():
    kwargs = dict(
        total=3,
        connect=3,
        read=3,
        backoff_factor=0.5,
        status_forcelist=(429, 500, 502, 503, 504),
        raise_on_status=False,
    )
    # urllib3 renamed method_whitelist -> allowed_methods in 1.26
    try:
        return Retry(allowed_methods=frozenset(['GET']), **kwargs)
    except TypeError:
        return Retry(method_whitelist=frozenset(['GET']), **kwargs)


def get_session():
    sess = getattr(_local, 'session', None)
    if sess is None:
        sess = requests.Session()
        sess.headers.update({'User-Agent': USER_AGENT})
        adapter = HTTPAdapter(max_retries=_build_retry(), pool_maxsize=4)
        sess.mount('https://', adapter)
        sess.mount('http://', adapter)
        _local.session = sess
    return sess


# ---------------------------------------------------------------------------
# Lyrics sources
# ---------------------------------------------------------------------------
class LyricsFetcher:
    """Fetches lyrics from a prioritised list of sources."""

    def __init__(self):
        # (label, callable) in priority order
        self.sources = [
            ('LRCLIB', self._lrclib),
            ('ChartLyrics', self._chartlyrics),
            ('lyrics.ovh', self._ovh),
        ]

    def _lrclib(self, artist, title):
        """LRCLIB — fast, reliable, and the only source here with synced lyrics."""
        resp = get_session().get(
            'https://lrclib.net/api/search',
            params={'artist_name': artist, 'track_name': title},
            timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            if data:
                synced = data[0].get('syncedLyrics') or ''
                plain = data[0].get('plainLyrics') or ''
                if synced:
                    return ('synced', synced)
                if plain:
                    return ('plain', plain)
        return None

    def _chartlyrics(self, artist, title):
        """ChartLyrics — XML API, plain lyrics only."""
        resp = get_session().get(
            'http://api.chartlyrics.com/apiv1.asmx/SearchLyricDirect',
            params={'artist': artist, 'song': title},
            timeout=10,
        )
        if resp.status_code == 200:
            root = ET.fromstring(resp.content)
            node = root.find('.//{http://api.chartlyrics.com/}Lyric')
            if node is not None and node.text:
                return ('plain', node.text)
        return None

    def _ovh(self, artist, title):
        """lyrics.ovh — path-based API, so artist/title must be URL-encoded."""
        url = f'https://api.lyrics.ovh/v1/{quote(artist)}/{quote(title)}'
        resp = get_session().get(url, timeout=10)
        if resp.status_code == 200:
            lyrics = resp.json().get('lyrics') or ''
            if lyrics:
                return ('plain', lyrics)
        return None

    def fetch(self, artist, title, emit):
        """Try each source in order. Returns (type, text) or None."""
        emit(f"  🔍 Fetching lyrics for: {artist} - {title}")
        for label, fn in self.sources:
            emit(f"  📡 Trying {label}...")
            try:
                result = fn(artist, title)
            except Exception as e:
                emit(f"  ⚠️  Error from {label}: {type(e).__name__}")
                continue
            if result:
                ltype, text = result
                emit(f"  ✅ Found {ltype} lyrics from {label}!")
                return (ltype, text.strip())
        emit("  ❌ No lyrics found from any source")
        return None


# ---------------------------------------------------------------------------
# Audio handling
# ---------------------------------------------------------------------------
class AudioParser:
    def __init__(self, directory, workers=6, delay=0.3, overwrite=False):
        self.directory = Path(directory).expanduser().resolve()
        self.workers = max(1, workers)
        self.delay = max(0.0, delay)
        self.overwrite = overwrite
        self.fetcher = LyricsFetcher()

    # -- metadata ----------------------------------------------------------
    @staticmethod
    def extract_metadata(audio_path, emit):
        """Return (artist, title) or (None, None)."""
        try:
            suffix = audio_path.suffix.lower()

            if suffix == '.flac':
                audio = FLAC(str(audio_path))
                artist = (audio.get('artist') or audio.get('ARTIST') or [None])[0]
                title = (audio.get('title') or audio.get('TITLE') or [None])[0]

            elif suffix == '.mp3':
                tags = MP3(str(audio_path)).tags
                artist = str(tags['TPE1'][0]) if tags and 'TPE1' in tags else None
                title = str(tags['TIT2'][0]) if tags and 'TIT2' in tags else None

            elif suffix in ('.m4a', '.mp4'):
                tags = MP4(str(audio_path)).tags
                artist = tags['\xa9ART'][0] if tags and '\xa9ART' in tags else None
                title = tags['\xa9nam'][0] if tags and '\xa9nam' in tags else None

            else:
                return None, None

            artist = artist.strip() if isinstance(artist, str) else artist
            title = title.strip() if isinstance(title, str) else title
            return (artist or None), (title or None)

        except Exception as e:
            emit(f"  ⚠️  Error reading metadata: {type(e).__name__}: {e}")
            return None, None

    # -- saving ------------------------------------------------------------
    @staticmethod
    def save_lyrics(audio_path, lyrics_type, lyrics, emit):
        out_path = audio_path.with_suffix('.lrc' if lyrics_type == 'synced' else '.txt')
        try:
            out_path.write_text(lyrics, encoding='utf-8')
            emit(f"  ✓ Saved to: {out_path.name}")
            return True
        except Exception as e:
            emit(f"  Error saving lyrics: {e}")
            return False

    # -- per-file worker ---------------------------------------------------
    def process_one(self, audio_path):
        """Worker. Returns (outcome, log_lines). Runs in a thread."""
        logs = []
        emit = logs.append
        emit(f"🎵 Processing: {audio_path.name}")

        if not self.overwrite:
            for ext in ('.lrc', '.txt'):
                existing = audio_path.with_suffix(ext)
                if existing.exists():
                    emit(f"  ⏭️  Skipping - lyrics file already exists ({existing.name})")
                    return ('skipped', logs)

        artist, title = self.extract_metadata(audio_path, emit)
        if not artist or not title:
            emit("  ⚠️  Skipping - missing artist or title metadata")
            return ('nometa', logs)

        result = self.fetcher.fetch(artist, title, emit)
        if self.delay:
            time.sleep(self.delay)  # gentle pacing per worker

        if not result:
            return ('notfound', logs)

        lyrics_type, lyrics = result
        if self.save_lyrics(audio_path, lyrics_type, lyrics, emit):
            return ('found', logs)
        return ('error', logs)

    # -- directory scan ----------------------------------------------------
    def find_audio_files(self):
        """Single os.walk pass, filtered by extension (case-insensitive)."""
        files = []
        for dirpath, _dirs, names in os.walk(self.directory):
            for name in names:
                if os.path.splitext(name)[1].lower() in AUDIO_EXTS:
                    files.append(Path(dirpath) / name)
        return sorted(files)

    # -- orchestration -----------------------------------------------------
    def run(self):
        if not self.directory.exists():
            print(f"❌ Error: Directory '{self.directory}' does not exist", flush=True)
            return

        print(f"🔍 Searching for audio files in: {self.directory}", flush=True)
        audio_files = self.find_audio_files()
        if not audio_files:
            print("❌ No audio files found", flush=True)
            return

        print(f"📁 Found {len(audio_files)} audio files (FLAC, MP3, M4A/ALAC)", flush=True)
        print(f"⚙️  Using {self.workers} workers, {self.delay}s pacing\n", flush=True)
        print("=" * 60, flush=True)

        counts = {'found': 0, 'skipped': 0, 'nometa': 0, 'notfound': 0, 'error': 0}

        with ThreadPoolExecutor(max_workers=self.workers) as pool:
            futures = {pool.submit(self.process_one, p): p for p in audio_files}
            for fut in as_completed(futures):
                try:
                    outcome, logs = fut.result()
                except Exception as e:
                    path = futures[fut]
                    print(f"\n🎵 {path.name}\n  ⚠️  Unexpected error: {e}", flush=True)
                    counts['error'] += 1
                    continue
                counts[outcome] = counts.get(outcome, 0) + 1
                print("\n" + "\n".join(logs), flush=True)

        total = sum(counts.values())
        print("\n" + "=" * 60, flush=True)
        print("📊 Summary:", flush=True)
        print(f"  Total files:      {total}", flush=True)
        print(f"  Lyrics found:     {counts['found']} ✓", flush=True)
        print(f"  Already had file: {counts['skipped']}", flush=True)
        print(f"  No metadata:      {counts['nometa']}", flush=True)
        print(f"  Not found:        {counts['notfound']}", flush=True)
        print(f"  Save errors:      {counts['error']}", flush=True)


def main():
    # line-buffer stdout so the Flask SSE console streams promptly
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    parser = argparse.ArgumentParser(
        description="Fetch lyrics for FLAC/MP3/M4A files (LRCLIB, ChartLyrics, lyrics.ovh)."
    )
    parser.add_argument('directory', help='Root directory to search recursively')
    parser.add_argument('-w', '--workers', type=int, default=6,
                        help='Concurrent fetch workers (default: 6)')
    parser.add_argument('-d', '--delay', type=float, default=0.3,
                        help='Per-worker pacing delay in seconds (default: 0.3)')
    parser.add_argument('--overwrite', action='store_true',
                        help='Re-fetch even if a .lrc/.txt already exists')
    args = parser.parse_args()

    print("🎼 Audio Lyrics Fetcher\n", flush=True)
    AudioParser(
        args.directory,
        workers=args.workers,
        delay=args.delay,
        overwrite=args.overwrite,
    ).run()


if __name__ == "__main__":
    main()
