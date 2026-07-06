# Timelapse

Year-long timelapse project using an ESP32-S3 Eye camera at 65°N. Captures the full seasonal cycle — midnight sun in summer, near-darkness in winter.

## Hardware

- [ESP32-S3 Eye](https://www.aliexpress.com/item/1005004960637276.html) (OV2640/OV5640 camera, built-in SD card slot)
- Raspberry Pi 3B (image storage server)
- Power: powerbank on mains (provides power during outages without needing a battery change)

## How it works

The ESP32 captures one JPEG per minute at XGA (1024×768) resolution. Each image is:
1. Uploaded directly to the Pi over WiFi via HTTP POST (framebuffer → network, SD never written)
2. If the upload fails or WiFi is down, the image is saved to the SD card as a queue entry
3. Queued images are retried automatically — oldest first — once connectivity returns

The SD card is purely a fallback buffer. Under normal conditions (WiFi up, Pi reachable) it is never touched, which reduces SD wear.

## File structure

Images are stored on the Pi under `/home/<username>/timelapse/`, grouped by camera name then date:

```
/home/<username>/timelapse/
  plant/
    2026-04-23/
      2026-04-23_06-00.jpg
      2026-04-23_06-01.jpg
      ...
    2026-04-24/
      ...
  cam2/
    2026-04-23/
      ...
```

The timestamp in every filename is UTC, with minute precision. Alphabetical order is chronological order — ffmpeg sorts correctly without extra flags.

Camera identity is determined by the source IP of the upload request — no firmware change needed. Each camera must have a stable IP (configure a static DHCP reservation in your router). The IP → name mapping lives in `CAMERAS` at the top of `pi/server.py`.

## Setup

### ESP32

1. Open `Timelapse.ino` in Arduino IDE
2. Copy `config.example.h` to `config.h` and fill in your values:
   - Set `WIFI_SSID` and `WIFI_PASSWORD`
   - Set `SERVER_IP` to the Pi's reserved IP address
3. Board settings:
   - Board: `ESP32S3 Dev Module`
   - PSRAM: `OPI PSRAM`
   - Partition scheme: `Huge APP (3MB No OTA / 1MB SPIFFS)` or larger
4. Flash and verify serial output shows NTP sync and first capture

### Raspberry Pi

> Replace `<username>` with your actual Raspberry Pi username throughout all commands below. The deploy script handles substitution in `server.py` and `timelapse.service` automatically.

Create the server directory and install Flask in a virtual environment (required on Raspberry Pi OS Bookworm):
```bash
mkdir -p /home/<username>/timelapse-server
python3 -m venv /home/<username>/timelapse-server/venv
/home/<username>/timelapse-server/venv/bin/pip install flask
```

Copy `pi.conf.example` to `pi.conf` and fill in your username and Pi IP — this is used by the deploy script and is gitignored so it never gets committed:
```bash
cp pi.conf.example pi.conf
```

Copy the service file to the Pi and install it (first time only):
```bash
scp pi/timelapse.service <username>@192.168.1.xxx:/home/<username>/timelapse-server/timelapse.service
ssh <username>@192.168.1.xxx "sudo cp /home/<username>/timelapse-server/timelapse.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable timelapse"
```

Test the server manually before starting it as a service:
```bash
ssh <username>@192.168.1.xxx "/home/<username>/timelapse-server/venv/bin/python /home/<username>/timelapse-server/server.py"
curl http://192.168.1.xxx:5000/status
```

Start the service:
```bash
ssh <username>@192.168.1.xxx "sudo systemctl start timelapse && sudo systemctl status timelapse"
```

For all future updates to `server.py`, use the deploy script — it substitutes `<username>`, uploads, and restarts the service in one step:
```bash
./deploy.sh
```

## Rendering on Mac

Requires `ffmpeg`. Homebrew's default `ffmpeg` formula is built **without libass**, so it has no `subtitles` filter — needed for the `--timestamp` overlay in `make_timelapse.sh`. Install the full build instead:
```bash
brew install ffmpeg-full
brew link --overwrite ffmpeg-full
```
(`ffmpeg-full` is keg-only, so it needs an explicit link. Plain `brew install ffmpeg` is fine if you never use `--timestamp`.)

First download and clean up images from the Pi using the download script:
```bash
./download.sh
```

This transfers all images to `LOCAL_DIR` (set in `pi.conf`) and deletes them from the Pi as they are confirmed received — keeping the Pi's SD card free for the next period. A confirmation prompt is shown before anything is deleted.

### Selecting frames — `select_frames.sh`

`select_frames.sh` builds a `frames.txt` suitable for `make_timelapse.sh`. It reads `LOCAL_DIR` from `pi.conf` automatically.

```
Usage: ./select_frames.sh -c <cam> [-d <date>] [-i <interval>] [-o <output>]

  -c, --cam        Camera name (required, e.g. plant)
  -d, --date       Starting date YYYY-MM-DD — include this day and all following (default: all)
  -i, --interval   Keep every Nth frame, 1 = all (default: 1)
  -o, --output     Output file (default: frames.txt)
```

Examples:

```bash
# All frames for plant camera (full history)
./select_frames.sh --cam plant

# From a date onwards, every 30th frame (~30-minute intervals at 1 fps capture)
./select_frames.sh --cam plant --date 2026-07-01 --interval 30 --output july_30min.txt

# Single day, every 5th frame
./select_frames.sh --cam plant --date 2026-07-15 --interval 5

# Then render:
./make_timelapse.sh frames.txt output.mp4
```

macOS creates hidden `._` resource fork files alongside every JPEG — `select_frames.sh` and `make_timelapse.sh` both filter these out automatically.

### Batch rendering — `batch_timelapse.sh`

Renders one timelapse per camera per day automatically. Already-rendered files are skipped unless new frames have arrived since the last render.

```bash
./batch_timelapse.sh                    # output to current directory
./batch_timelapse.sh /Volumes/Drive/out # output to a specific directory
```

Output files are named `<camera><date>.mp4` (e.g. `plant2026-07-15.mp4`). Reads `LOCAL_DIR` from `pi.conf`.

### Rotating frames — `rotate_frames.sh`

If a camera was mounted upside-down for a period, use this to fix the frames in-place. Rotation is lossless (via `jpegtran`) and each corrected file is tagged with a JPEG comment so already-rotated images are never processed twice.

Requires `libjpeg-turbo` and `exiftool`:
```bash
brew install jpeg-turbo exiftool
```

```
Usage: ./rotate_frames.sh <camera> <from_timestamp>

  camera          — e.g. plant, cam2
  from_timestamp  — inclusive start, matched as filename prefix:
                    2026-05-30        (whole day onwards)
                    2026-05-30_10-30  (from 10:30 UTC onwards)
```

Example:
```bash
./rotate_frames.sh plant 2026-05-30
./rotate_frames.sh plant 2026-05-30_10-30
```

A confirmation prompt is shown before any files are modified.

### Single-day render

```bash
./select_frames.sh --cam plant --date 2026-07-15 -o frames.txt
./make_timelapse.sh frames.txt day_2026-07-15.mp4

# Slower playback (12fps):
./make_timelapse.sh frames.txt day_2026-07-15_slow.mp4 12
```

### Timestamp overlay

Add `--timestamp` to burn the UTC date and time onto each frame:

```bash
./make_timelapse.sh frames.txt day_timestamped.mp4 24 --timestamp
```

This generates a per-frame SRT subtitle file and burns it in via ffmpeg's `subtitles` filter, which requires `ffmpeg-full` (see [Rendering on Mac](#rendering-on-mac) above) — the default `ffmpeg` formula lacks libass and will fail with a filter-parsing error. Temp files (`frames_clean.txt`, `timestamps.srt`) are cleaned up automatically when the script exits.

### Output format options

XGA (1024×768) is 4:3. All examples above use 1080p letterboxed to 16:9 (black bars top/bottom). Alternatives:

```bash
# Native 4:3 — no scaling, sharpest
-vf "scale=1024:768"

# Cropped to 16:9 — fills the screen, slight crop on sides
-vf "scale=1920:1440,crop=1920:1080:0:180"
```

---

## Interval tiers quick reference

All tiers are derived from the 1-minute source — no re-shooting needed.

| Tier | `--interval` | Frames/year | Video @ 24fps |
|------|-------------|-------------|---------------|
| 1 min | `1` (all) | ~525,000 | ~6 hours |
| 5 min | `5` | ~105,000 | ~73 min |
| 15 min | `15` | ~35,000 | ~24 min |
| 30 min | `30` | ~17,500 | ~12 min |
| 60 min | `60` | ~8,760 | ~6 min |

## Storage reference

At 1-minute interval, 24/7, at 65°N (accounting for dark nights compressing well):

| Storage | Capacity | Rate | Notes |
|---------|----------|------|-------|
| Pi SD (64 GB) | ~56 GB usable | ~6 GB/month | Clean every 3 months, never at risk |
| ESP32 SD (8 GB) | 8 GB | ~180 MB/day avg | Buffers ~45 days of Pi outage |

## Browsing images

Open `http://192.168.1.xxx:5000` in a browser to browse images on the Pi.

> **macOS Tahoe:** Go to System Settings → Privacy & Security → Local Network and enable access for your browser if it can't reach the Pi.

- **`/`** — list of all cameras with total image count
- **`/<camera>`** — list of all days for that camera, newest first
- **`/<camera>/day/<date>`** — hours in that day, with image count per hour
- **`/<camera>/day/<date>/<hour>`** — full image grid for that hour, lazy-loaded

Clicking any image opens it at full XGA resolution in a new tab.

### Adding a camera

1. Assign the new ESP32 a static IP in the router's DHCP reservation settings.
2. Add the entry to `CAMERAS` in `pi/server.py`:
   ```python
   CAMERAS = {
       "192.168.1.73":  "plant",
       "192.168.1.101": "new-camera",
   }
   ```
3. Run `./deploy.sh` to push the updated server to the Pi.

Cameras not listed in `CAMERAS` are still accepted — the server uses the last two octets of the source IP as the camera name (e.g. `192.168.1.101` → `1.101`). This lets a new camera start uploading immediately while you decide on a permanent name.

## Monitoring

Check image count per camera and disk space:
```bash
curl http://192.168.1.xxx:5000/status
```

Check server logs:
```bash
tail -f /home/<username>/timelapse-server/server.log
```
