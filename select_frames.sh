#!/bin/bash
# Build a frames.txt file for use with make_timelapse.sh.
#
# Usage: select_frames.sh -c <cam> [-d <date>] [-i <interval>] [-o <output>]
#
# Options:
#   -c, --cam        Camera name (required, e.g. plant)
#   -d, --date       Starting date YYYY-MM-DD — include this day and all following (default: all)
#   -i, --interval   Keep every Nth frame, 1 = all (default: 1)
#   -o, --output     Output file (default: frames.txt)
#
# Examples:
#   ./select_frames.sh --cam plant
#   ./select_frames.sh --cam plant --date 2026-07-01
#   ./select_frames.sh --cam plant --date 2026-07-15 --interval 5
#   ./select_frames.sh --cam plant --interval 30 --output year_30min.txt

set -euo pipefail

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

CAM=""
DATE=""
INTERVAL=1
OUTPUT="frames.txt"

usage() {
  echo "Usage: $(basename "$0") -c <cam> [-d <date>] [-i <interval>] [-o <output>]"
  echo ""
  echo "Options:"
  echo "  -c, --cam        Camera name (required, e.g. plant)"
  echo "  -d, --date       Starting date YYYY-MM-DD — include this day and all following (default: all)"
  echo "  -i, --interval   Keep every Nth frame, 1 = all (default: 1)"
  echo "  -o, --output     Output file (default: frames.txt)"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") --cam plant"
  echo "  $(basename "$0") --cam plant --date 2026-07-01"
  echo "  $(basename "$0") --cam plant --date 2026-07-15 --interval 5"
  echo "  $(basename "$0") --cam plant --interval 30 --output year_30min.txt"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--cam)
      CAM="${2:-}"
      [ -n "$CAM" ] || { echo "Error: --cam requires a value" >&2; exit 1; }
      shift 2 ;;
    -d|--date)
      DATE="${2:-}"
      [ -n "$DATE" ] || { echo "Error: --date requires a value" >&2; exit 1; }
      shift 2 ;;
    -i|--interval)
      INTERVAL="${2:-}"
      [ -n "$INTERVAL" ] || { echo "Error: --interval requires a value" >&2; exit 1; }
      shift 2 ;;
    -o|--output)
      OUTPUT="${2:-}"
      [ -n "$OUTPUT" ] || { echo "Error: --output requires a value" >&2; exit 1; }
      shift 2 ;;
    -h|--help)
      usage
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1 ;;
  esac
done

if [ -z "$CAM" ]; then
  echo "Error: --cam is required" >&2
  usage >&2
  exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
  echo "Error: --interval must be a positive integer (got: $INTERVAL)" >&2
  exit 1
fi

CAM_DIR="$LOCAL_DIR/$CAM"
if [ ! -d "$CAM_DIR" ]; then
  echo "Error: camera directory not found: $CAM_DIR" >&2
  exit 1
fi

if [ -n "$DATE" ] && ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: invalid date format '$DATE' (use YYYY-MM-DD)" >&2
  exit 1
fi

DATE_LABEL="${DATE:+from $DATE}"
echo "cam=$CAM  date=${DATE_LABEL:-all}  interval=$INTERVAL  output=$OUTPUT"

run_find() {
  if [ -z "$DATE" ]; then
    find "$CAM_DIR" -name "*.jpg" ! -name "._*"
  else
    # YYYY-MM-DD directory names sort lexicographically == chronologically
    for dir in "$CAM_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/; do
      [ -d "$dir" ] || continue
      day=$(basename "$dir")
      [[ ! "$day" < "$DATE" ]] && find "$dir" -name "*.jpg" ! -name "._*"
    done
  fi
}

run_find \
  | sort \
  | awk -v n="$INTERVAL" '(NR - 1) % n == 0' \
  | sed "s|^|file '|; s|$|'|" \
  > "$OUTPUT"

COUNT=$(grep -c "^file" "$OUTPUT" 2>/dev/null || echo 0)

if [ "$COUNT" -eq 0 ]; then
  echo "Warning: no frames found — $OUTPUT is empty" >&2
  exit 1
fi

echo "Written $COUNT frames to $OUTPUT"
