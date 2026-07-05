#!/bin/bash
# Render one timelapse per camera per day from frames stored in LOCAL_DIR.
# Output files are named <camera><date>.mp4 (e.g. plant2026-05-30.mp4).
#
# Usage: ./batch_timelapse.sh [output_dir]
#   output_dir  — where to write .mp4 files (default: current directory)
#
# Reads LOCAL_DIR from pi.conf alongside this script.
# Already-rendered files are skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/pi.conf"
MAKE_TIMELAPSE="$SCRIPT_DIR/make_timelapse.sh"

if [ ! -f "$CONF" ]; then
  echo "Error: pi.conf not found at $CONF" >&2
  exit 1
fi

# shellcheck source=pi.conf
source "$CONF"

if [ -z "${LOCAL_DIR:-}" ]; then
  echo "Error: LOCAL_DIR not set in pi.conf" >&2
  exit 1
fi

if [ ! -d "$LOCAL_DIR" ]; then
  echo "Error: LOCAL_DIR not found: $LOCAL_DIR" >&2
  exit 1
fi

OUTPUT_DIR="${1:-$(pwd)}"
mkdir -p "$OUTPUT_DIR"

FRAMES_TMP=$(mktemp /tmp/frames_XXXXXX.txt)
trap 'rm -f "$FRAMES_TMP"' EXIT

for cam_dir in "$LOCAL_DIR"/*/; do
  [ -d "$cam_dir" ] || continue
  cam=$(basename "$cam_dir")

  for day_dir in "$cam_dir"*/; do
    [ -d "$day_dir" ] || continue
    day=$(basename "$day_dir")

    [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue

    output="$OUTPUT_DIR/${cam}${day}.mp4"

    find "$day_dir" -name "*.jpg" | sort \
      | sed "s|^|file '|; s|$|'|" > "$FRAMES_TMP"

    count=$(grep -c "^file" "$FRAMES_TMP" 2>/dev/null || echo 0)
    if [ "$count" -eq 0 ]; then
      echo "Skip  $cam / $day  (no frames)"
      continue
    fi

    if [ -f "$output" ]; then
      newer=$(find "$day_dir" -name "*.jpg" -newer "$output" -print -quit 2>/dev/null)
      if [ -z "$newer" ]; then
        echo "Skip  $cam / $day  (up to date, $count frames)"
        continue
      fi
    fi

    echo "Render  $cam / $day  ($count frames) → $(basename "$output")"
    if ! "$MAKE_TIMELAPSE" "$FRAMES_TMP" "$output"; then
      echo "Error: render failed for $cam / $day" >&2
    fi
  done
done

echo "Done."
