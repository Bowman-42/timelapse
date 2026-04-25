#!/bin/bash
# Create a timelapse video from a frames.txt file.
# Optionally burns a UTC timestamp overlay onto each frame.
#
# Usage:
#   ./make_timelapse.sh <frames.txt> <output.mp4> [fps] [--timestamp]
#
# Examples:
#   ./make_timelapse.sh frames.txt year.mp4
#   ./make_timelapse.sh frames.txt year.mp4 24 --timestamp

set -e

FRAMES=${1:-frames.txt}
OUTPUT=${2:-timelapse.mp4}
FPS=${3:-24}
TIMESTAMP=${4:-}

if [ ! -f "$FRAMES" ]; then
  echo "Error: frames file not found: $FRAMES"
  exit 1
fi

# Strip macOS resource fork files (._*) — they sort before real JPEGs
# alphabetically and would cause timestamps to repeat for each day.
CLEAN_FRAMES="${FRAMES%.txt}_clean.txt"
SRT_FILE="$(pwd)/timestamps.srt"
trap 'rm -f "$CLEAN_FRAMES" "$SRT_FILE"' EXIT
grep -v "/\._" "$FRAMES" > "$CLEAN_FRAMES"
INPUT="$CLEAN_FRAMES"

COUNT=$(grep -c "^file" "$INPUT")
echo "Rendering $COUNT frames at ${FPS}fps → $OUTPUT"

if [ "$TIMESTAMP" = "--timestamp" ]; then
  echo "Generating subtitle file from frame timestamps..."

  python3 - "$INPUT" "$FPS" <<'EOF'
import re, sys

frames_file = sys.argv[1]
fps = float(sys.argv[2])

with open(frames_file) as f:
    lines = [l.strip() for l in f if l.strip().startswith("file")]

paths = [l.removeprefix("file").strip().strip("'") for l in lines]

def ms_to_srt(ms):
    h = ms // 3600000
    m = (ms % 3600000) // 60000
    s = (ms % 60000) // 1000
    cs = ms % 1000
    return f"{h:02d}:{m:02d}:{s:02d},{cs:03d}"

idx = 0
with open("timestamps.srt", "w") as out:
    for i, path in enumerate(paths):
        m = re.search(r'(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2})\.jpg', path)
        if not m:
            continue
        idx += 1
        label = f"{m.group(1)} {m.group(2).replace('-', ':')} UTC"
        start_ms = int(i * 1000 / fps)
        end_ms = int((i + 1) * 1000 / fps)
        out.write(f"{idx}\n{ms_to_srt(start_ms)} --> {ms_to_srt(end_ms)}\n{label}\n\n")

print(f"Written {idx} subtitle entries to timestamps.srt")
EOF

  VF="scale=1440:1080,pad=1920:1080:240:0:black,subtitles=${SRT_FILE}:force_style='Fontsize=16,PrimaryColour=&H00FFFFFF,BackColour=&H80000000,BorderStyle=4,Alignment=1,MarginL=10,MarginV=10'"
else
  VF="scale=1440:1080,pad=1920:1080:240:0:black"
fi

ffmpeg -loglevel error -stats \
  -r "$FPS" -f concat -safe 0 -i "$INPUT" \
  -vf "$VF" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUTPUT"

echo "Done: $OUTPUT"
