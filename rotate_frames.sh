#!/bin/bash
# Rotate all frames for a camera from a given timestamp onwards by 180°.
# Uses jpegtran for lossless pixel rotation and tags each image with a
# JPEG comment so rotated frames can be identified later.
# Already-tagged images are skipped.
#
# Usage: ./rotate_frames.sh <camera> <from_timestamp>
#   camera          — camera name, e.g. plant, cam2, cam3
#   from_timestamp  — inclusive start, matched as a filename prefix
#                     e.g. 2026-05-30          (whole day onwards)
#                          2026-05-30_10-30    (from 10:30 UTC onwards)
#
# To list all rotated images afterwards:
#   exiftool -q -r -if '$Comment eq "rotated-180"' -p '$Directory/$FileName' <cam_dir>

set -euo pipefail

if ! command -v jpegtran &>/dev/null; then
  echo "Error: jpegtran not found. Install with: brew install jpeg-turbo" >&2
  exit 1
fi
if ! command -v exiftool &>/dev/null; then
  echo "Error: exiftool not found. Install with: brew install exiftool" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/pi.conf"

if [ ! -f "$CONF" ]; then
  echo "Error: pi.conf not found at $CONF" >&2
  exit 1
fi

source "$CONF"

if [ -z "${LOCAL_DIR:-}" ]; then
  echo "Error: LOCAL_DIR not set in pi.conf" >&2
  exit 1
fi

CAMERA="${1:-}"
FROM="${2:-}"

if [ -z "$CAMERA" ] || [ -z "$FROM" ]; then
  echo "Usage: $0 <camera> <from_timestamp>" >&2
  echo "  e.g. $0 plant 2026-05-30" >&2
  echo "       $0 plant 2026-05-30_10-30" >&2
  exit 1
fi

CAM_DIR="$LOCAL_DIR/$CAMERA"
if [ ! -d "$CAM_DIR" ]; then
  echo "Error: camera directory not found: $CAM_DIR" >&2
  exit 1
fi

# Collect all qualifying jpg files (sorted = chronological order).
# Filtering in the outer while loop (main shell) avoids subshell variable scoping issues.
echo "Scanning files..."
candidates=()
while IFS= read -r f; do
  base=$(basename "$f" .jpg)
  if [[ "$base" > "$FROM" || "$base" == "$FROM"* ]]; then
    candidates+=("$f")
  fi
done < <(find "$CAM_DIR" -name "*.jpg" | grep -v "/\._" | sort)

if [ ${#candidates[@]} -eq 0 ]; then
  echo "No frames found from $FROM onwards for camera $CAMERA"
  exit 0
fi

# Filter out already-rotated images using a single batched exiftool call.
echo "Checking for already-rotated images..."
FILELIST=$(mktemp /tmp/rotate_list_XXXXXX.txt)
ALREADY_ROTATED=$(mktemp /tmp/rotate_done_XXXXXX.txt)
TMP=$(mktemp /tmp/rotate_XXXXXX.jpg)
trap 'rm -f "$FILELIST" "$ALREADY_ROTATED" "$TMP"' EXIT

printf '%s\n' "${candidates[@]}" > "$FILELIST"
exiftool -q -if '$Comment eq "rotated-180"' -p '$Directory/$FileName' \
  -@ "$FILELIST" > "$ALREADY_ROTATED" 2>/dev/null || true

files=()
skipped=0
for f in "${candidates[@]}"; do
  if grep -qxF "$f" "$ALREADY_ROTATED"; then
    (( skipped++ )) || true
  else
    files+=("$f")
  fi
done

total=${#files[@]}
if [ "$total" -eq 0 ]; then
  echo "All $skipped frames in range already rotated — nothing to do."
  exit 0
fi

first=$(basename "${files[0]}" .jpg)
last=$(basename "${files[${#files[@]}-1]}" .jpg)
echo "Camera:   $CAMERA"
echo "Range:    $first → $last"
echo "To rotate: $total  (skipping $skipped already rotated)"
echo ""
read -p "Rotate $total images by 180°? This modifies files in-place. [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
count=0
for f in "${files[@]}"; do
  if ! jpegtran -rotate 180 -copy none -outfile "$TMP" "$f" 2>/dev/null; then
    echo "  Warning: skipping corrupt file: $f" >&2
    continue
  fi
  cp "$TMP" "$f"
  exiftool -q -overwrite_original -Comment="rotated-180" "$f"
  (( count++ )) || true
  if (( count % 200 == 0 )); then
    echo "  $count / $total"
  fi
done

echo "Done: rotated $count frames."
