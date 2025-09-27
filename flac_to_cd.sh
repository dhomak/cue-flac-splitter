#!/usr/bin/env bash
# flac_to_cd.sh — Recursively convert FLAC -> FLAC (16-bit / 44.1 kHz)
# Usage: flac_to_cd.sh INPUT_DIR OUTPUT_DIR
# Optional: DEBUG=1 ./flac_to_cd.sh IN OUT
set -euo pipefail
IFS=$'\n\t'
dbg(){ [[ "${DEBUG:-0}" == "1" ]] && echo "[DBG] $*" >&2 || true; }

# --- Args & setup ---
if [[ $# -ne 2 ]]; then echo "Usage: $0 INPUT_DIR OUTPUT_DIR" >&2; exit 2; fi
abs(){ (cd "$1" 2>/dev/null && pwd -P) || return 1; }

INDIR="$(abs "${1%/}")" || { echo "ERROR: input dir"; exit 1; }
mkdir -p "${2%/}" || true
OUTDIR="$(abs "${2%/}")" || { echo "ERROR: output dir"; exit 1; }

case "$OUTDIR" in "$INDIR"|"$INDIR"/*) echo "ERROR: OUTDIR inside INDIR"; exit 1;; esac
command -v ffmpeg >/dev/null  || { echo "ERROR: ffmpeg not found"; exit 1; }
command -v ffprobe >/dev/null || { echo "ERROR: ffprobe not found"; exit 1; }

# quick write test
: > "$OUTDIR/.write_test" 2>/dev/null || { echo "ERROR: cannot write to $OUTDIR"; exit 1; }
rm -f "$OUTDIR/.write_test" || true

# --- helpers ---
is_flac_16_441(){
  local f="$1" line codec rate bps
  line="$(ffprobe -v error -select_streams a:0 \
          -show_entries stream=codec_name,sample_rate,bits_per_sample \
          -of csv=p=0 "$f" 2>/dev/null || true)"
  IFS=',' read -r codec rate bps <<< "${line:-,,}"
  [[ "${codec:-}" == "flac" && "${rate:-}" == "44100" && "${bps:-}" == "16" ]]
}

# robust realpath for each *file* (handles symlinks, whitespace, trailing spaces)
file_realpath(){
  local p="$1" r=""
  if command -v python3 >/dev/null 2>&1; then
    r="$(python3 - <<'PY' "$p"
import os,sys; print(os.path.realpath(sys.argv[1]))
PY
    )" || r=""
  fi
  if [[ -z "$r" ]] && command -v realpath >/dev/null 2>&1; then
    r="$(realpath -e "$p" 2>/dev/null || true)"
  fi
  if [[ -z "$r" ]]; then
    # last resort: prefix with current working dir if relative
    case "$p" in /*) r="$p" ;; *) r="$(pwd -P)/$p" ;; esac
  fi
  printf '%s\n' "$r"
}

# make REL from absolute $src_abs relative to $INDIR (never absolute; never starts with ./)
rel_from_indir(){
  local p="$1" b="$2" r=""
  if command -v python3 >/dev/null 2>&1; then
    r="$(python3 - <<'PY' "$p" "$b"
import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
    )" || r=""
  fi
  if [[ -z "$r" ]] && command -v realpath >/dev/null 2>&1 && realpath --help 2>&1 | grep -q -- '--relative-to'; then
    r="$(realpath -m --relative-to="$b" "$p" 2>/dev/null || true)"
  fi
  if [[ -z "$r" ]]; then
    case "$p" in "$b"/*) r="${p#"$b"/}" ;; *) r="$(basename "$p")" ;; esac
  fi
  r="${r#./}"; r="${r#/}"; printf '%s\n' "$r"
}

# --- main loop ---
# Use process substitution to avoid subshell scoping issues
while IFS= read -r -d '' src; do
  # Get canonical absolute source path (prevents the “edia/…” truncation)
  src_abs="$(file_realpath "$src")"
  # Derive a clean relative path for destination layout
  rel="$(rel_from_indir "$src_abs" "$INDIR")"

  # Split into dir/name; strip extension only from the name
  rel_dir="$(dirname "$rel")"          # may be "."
  rel_name="$(basename "$rel")"
  base="${rel_name%.*}"

  dst_dir="$OUTDIR/$rel_dir"
  dst="$dst_dir/$base.flac"
  dst_disp="${dst#$OUTDIR/}"

  dbg "SRC_ABS=$src_abs"
  dbg "REL=$rel"
  dbg "DST_DIR=$dst_dir"
  dbg "DST=$dst"

  mkdir -p "$dst_dir" || { echo "ERROR: cannot create $dst_dir" >&2; continue; }
  if [[ -f "$dst" && "$dst" -nt "$src_abs" ]]; then echo "SKIP (up-to-date): $rel"; continue; fi
  if is_flac_16_441 "$src_abs" && [[ -f "$dst" ]]; then echo "SKIP (already 16/44.1): $rel"; continue; fi
  if [[ "$dst" == "$src_abs" ]]; then echo "ERROR: dst==src for $src_abs"; continue; fi

  echo "ENCODE: $rel -> $dst_disp"
  ffmpeg ${DEBUG:+-v verbose} -hide_banner -loglevel ${DEBUG:+info} ${DEBUG:-error} -nostdin -y \
    -i "$src_abs" \
    -vn \
    -c:a flac -sample_fmt s16 -ar 44100 -compression_level 8 \
    -map_metadata 0 \
    "$dst" || { echo "ERROR: ffmpeg failed on $rel" >&2; continue; }

  touch -r "$src_abs" "$dst" || true
  echo "DONE  : $dst_disp"
done < <(find "$INDIR" -type f -iname '*.flac' -print0)

echo "All done."

