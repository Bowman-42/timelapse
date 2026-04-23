# Timelapse

Year-long timelapse project using an ESP32-S3 Eye camera at 65°N. Captures the full seasonal cycle — midnight sun in summer, near-darkness in winter.

## Hardware

- [ESP32-S3 Eye](https://www.aliexpress.com/item/1005004960637276.html) (OV2640 camera, built-in SD card slot)
- Raspberry Pi 3B (image storage server)
- Power: powerbank on mains (provides power during outages without needing a battery change)

## How it works

The ESP32 captures one JPEG per minute at XGA (1024×768) resolution. Each image is:
1. Saved to the SD card immediately
2. Uploaded to the Pi over WiFi via HTTP POST
3. Deleted from the SD card after a confirmed upload

If WiFi or the Pi is unavailable, images accumulate on the SD card and are retried automatically — oldest first — once connectivity returns.

## File structure

Images are stored on the Pi under `/home/<username>/timelapse/`:

```
/home/<username>/timelapse/
  2026-04-23/
    2026-04-23_06-00.jpg
    2026-04-23_06-01.jpg
    ...
  2026-04-24/
    ...
```

The timestamp in every filename is UTC, with minute precision. Alphabetical order is chronological order — ffmpeg sorts correctly without extra flags.

## Setup

### ESP32

1. Open `Timelapse.ino` in Arduino IDE
2. Edit `config.h`:
   - Set `WIFI_SSID` and `WIFI_PASSWORD`
   - Set `SERVER_IP` to the Pi's reserved IP address
3. Board settings:
   - Board: `ESP32S3 Dev Module`
   - PSRAM: `OPI PSRAM`
   - Partition scheme: `Huge APP (3MB No OTA / 1MB SPIFFS)` or larger
4. Flash and verify serial output shows NTP sync and first capture

### Raspberry Pi

> Replace `<username>` with your actual Raspberry Pi username throughout all commands below, and in `server.py` and `timelapse.service` before copying them to the Pi.

Create the server directory and install Flask in a virtual environment (required on Raspberry Pi OS Bookworm):
```bash
mkdir -p /home/<username>/timelapse-server
python3 -m venv /home/<username>/timelapse-server/venv
/home/<username>/timelapse-server/venv/bin/pip install flask
```

Edit `pi/server.py` and `pi/timelapse.service` — replace `<username>` with your username — then copy to the Pi:
```bash
scp pi/server.py <username>@192.168.1.xxx:/home/<username>/timelapse-server/server.py
scp pi/timelapse.service <username>@192.168.1.xxx:/home/<username>/timelapse-server/timelapse.service
```

Test manually:
```bash
/home/<username>/timelapse-server/venv/bin/python /home/<username>/timelapse-server/server.py
curl http://192.168.1.xxx:5000/status
```

Install as a service so it starts on boot:
```bash
sudo cp /home/<username>/timelapse-server/timelapse.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable timelapse
sudo systemctl start timelapse
```

Check it is running:
```bash
sudo systemctl status timelapse
```

## Creating movies with ffmpeg

All commands run on the Pi. `cd` to the timelapse directory first:

```bash
cd /home/pi/timelapse
```

The general pattern is:
1. Use `find` + `grep` to select the frames you want
2. Pipe into a file list
3. Feed that list to ffmpeg

### Helper function (add to ~/.bashrc for convenience)

```bash
make_timelapse() {
  # Usage: make_timelapse <frame_list_file> <output.mp4> [fps]
  local frames=$1
  local output=$2
  local fps=${3:-24}
  ffmpeg -r "$fps" -f concat -safe 0 -i "$frames" \
    -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$output"
}
```

---

### Full year — 30-minute interval (~17,500 frames → ~12 min at 24fps)

Best for showing the seasonal arc. Uses only shots taken at :00 and :30.

```bash
find . -name "*.jpg" | grep -E "_(00|30)\.jpg$" | sort \
  | sed "s|^|file '$(pwd)/|; s|$|'|" > frames.txt

ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart year_30min.mp4
```

### Full year — 60-minute interval (~8,760 frames → ~6 min at 24fps)

```bash
find . -name "*.jpg" | grep -E "-00\.jpg$" | sort \
  | sed "s|^|file '$(pwd)/|; s|$|'|" > frames.txt

ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart year_60min.mp4
```

### Single month — 15-minute interval

```bash
find ./2026-07-* -name "*.jpg" | grep -E "-(00|15|30|45)\.jpg$" | sort \
  | sed "s|^|file '$(pwd)/|; s|$|'|" > frames.txt

ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart july_15min.mp4
```

### Single week — 5-minute interval

```bash
find ./2026-07-14 ./2026-07-15 ./2026-07-16 ./2026-07-17 \
     ./2026-07-18 ./2026-07-19 ./2026-07-20 \
  -name "*.jpg" | grep -E "-(00|05|10|15|20|25|30|35|40|45|50|55)\.jpg$" | sort \
  | sed "s|^|file '$(pwd)/|; s|$|'|" > frames.txt

ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart week_5min.mp4
```

### Single day — all frames, 1-minute interval (~1,440 frames → ~60 sec at 24fps)

```bash
find ./2026-07-15 -name "*.jpg" | sort \
  | sed "s|^|file '$(pwd)/|; s|$|'|" > frames.txt

ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart day_2026-07-15.mp4
```

### Single day — slower playback (12fps) for more detail

```bash
ffmpeg -r 12 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart day_2026-07-15_slow.mp4
```

---

## Interval tiers quick reference

All tiers are derived from the 1-minute source — no re-shooting needed.

| Tier | grep pattern | Frames/year | Video @ 24fps |
|------|-------------|-------------|---------------|
| 1 min | `*.jpg` (all) | ~525,000 | ~6 hours |
| 5 min | `-(00\|05\|10\|15\|20\|25\|30\|35\|40\|45\|50\|55)\.jpg` | ~105,000 | ~73 min |
| 15 min | `-(00\|15\|30\|45)\.jpg` | ~35,000 | ~24 min |
| 30 min | `-(00\|30)\.jpg` | ~17,500 | ~12 min |
| 60 min | `-00\.jpg` | ~8,760 | ~6 min |

## Rendering on Mac

Download images from the Pi first (replace `<username>`):
```bash
rsync -av --progress <username>@192.168.1.xxx:/home/<username>/timelapse/ ~/timelapse/
```

Then run ffmpeg locally. SVGA (800×600) is a 4:3 aspect ratio — use one of these output options:

```bash
# Native 4:3 at source resolution (crisp, no upscaling)
ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart output_native.mp4

# Upscaled to 1080p, letterboxed to 16:9 (black bars top/bottom)
ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -vf "scale=1440:1080,pad=1920:1080:240:0:black" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart output_1080p.mp4

# Upscaled to 1080p, cropped to 16:9 (slight crop on sides)
ffmpeg -r 24 -f concat -safe 0 -i frames.txt \
  -vf "scale=1920:1440,crop=1920:1080:0:180" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart output_1080p_crop.mp4
```

## Storage reference

At 1-minute interval, 24/7, at 65°N (accounting for dark nights compressing well):

| Storage | Capacity | Rate | Notes |
|---------|----------|------|-------|
| Pi SD (64 GB) | ~56 GB usable | ~6 GB/month | Clean every 3 months, never at risk |
| ESP32 SD (8 GB) | 8 GB | ~180 MB/day avg | Buffers ~45 days of Pi outage |

## Monitoring

Check how many images have been received and how much disk space is left:

```bash
curl http://192.168.1.xxx:5000/status
```

Check server logs:
```bash
tail -f /home/<username>/timelapse-server/server.log
```
