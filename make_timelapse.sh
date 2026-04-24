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

COUNT=$(grep -c "^file" "$FRAMES")
echo "Rendering $COUNT frames at ${FPS}fps → $OUTPUT"

if [ "$TIMESTAMP" = "--timestamp" ]; then
  echo "Generating timestamp subtitles..."

  python3 - "$FRAMES" <<'EOF'
import re, sys

with open(sys.argv[1]) as f:
    lines = [l.strip() for l in f if l.strip().startswith("file")]

paths = [l.removeprefix("file").strip().strip("'") for l in lines]

def fmt(n, fps=24):
    ms = int(n * (1000 / fps))
    return f"{ms//3600000:02d}:{(ms%3600000)//60000:02d}:{(ms%60000)//1000:02d},{ms%1000:03d}"

with open("subtitles.srt", "w") as out:
    for i, path in enumerate(paths):
        m = re.search(r'(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2})\.jpg', path)
        if not m:
            continue
        date, time = m.group(1), m.group(2).replace("-", ":")
        out.write(f"{i+1}\n{fmt(i)} --> {fmt(i+1)}\n{date} {time} UTC\n\n")

print(f"Written {len(paths)} subtitle entries to subtitles.srt")
EOF

  VF="scale=1440:1080,pad=1920:1080:240:0:black,subtitles=subtitles.srt:force_style=FontSize=28\,PrimaryColour=&Hffffff\,BackColour=&H80000000\,BorderStyle=4\,MarginV=20"
else
  VF="scale=1440:1080,pad=1920:1080:240:0:black"
fi

ffmpeg -loglevel error -stats \
  -r "$FPS" -f concat -safe 0 -i "$FRAMES" \
  -vf "$VF" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$OUTPUT"

echo "Done: $OUTPUT"
