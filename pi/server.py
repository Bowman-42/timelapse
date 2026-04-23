#!/usr/bin/env python3
"""
Timelapse image receiver — runs on Raspberry Pi.

Receives JPEG POSTs from the ESP32-S3 and saves them into:
  BASE_DIR/<X-Folder>/<X-Filename>

e.g. /home/<username>/timelapse/2026-04-23/2026-04-23_14-30.jpg

Start manually:  python3 server.py
As a service:    see timelapse.service
"""

import os
import logging
from flask import Flask, request, abort, send_from_directory
from markupsafe import escape

# --- Configuration -----------------------------------------------------------
# Replace <username> with your actual Raspberry Pi username

BASE_DIR = "/home/<username>/timelapse"   # where images are stored
PORT     = 5000
HOST     = "0.0.0.0"             # accept from any network interface

# -----------------------------------------------------------------------------

app = Flask(__name__)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.join(os.path.dirname(__file__), "server.log")),
    ],
)
log = logging.getLogger(__name__)

# --- Shared HTML chrome ------------------------------------------------------

def page(title, body):
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  body {{ font-family: sans-serif; max-width: 1200px; margin: 0 auto; padding: 1rem; background: #111; color: #eee; }}
  h1   {{ font-size: 1.4rem; margin-bottom: 1rem; }}
  a    {{ color: #7af; text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  .breadcrumb {{ font-size: 0.85rem; margin-bottom: 1.5rem; color: #aaa; }}
  .breadcrumb a {{ color: #aaa; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 0.5rem; }}
  .card {{ background: #222; border-radius: 6px; padding: 0.75rem; }}
  .card a {{ display: block; font-size: 1rem; }}
  .card .count {{ font-size: 0.8rem; color: #888; margin-top: 0.25rem; }}
  .img-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 0.4rem; }}
  .img-grid a img {{ width: 100%; border-radius: 4px; display: block; }}
  .img-label {{ font-size: 0.75rem; color: #888; text-align: center; margin-top: 0.2rem; }}
</style>
</head>
<body>
{body}
</body>
</html>"""


# --- Routes: browse ----------------------------------------------------------

@app.route("/")
def index():
    """List all days, newest first."""
    if not os.path.isdir(BASE_DIR):
        return page("Timelapse", "<h1>Timelapse</h1><p>No images yet.</p>")

    days = sorted(
        [d for d in os.listdir(BASE_DIR) if os.path.isdir(os.path.join(BASE_DIR, d))],
        reverse=True,
    )

    cards = ""
    for day in days:
        day_dir = os.path.join(BASE_DIR, day)
        count = sum(1 for f in os.listdir(day_dir) if f.endswith(".jpg"))
        cards += f"""
        <div class="card">
          <a href="/day/{escape(day)}">{escape(day)}</a>
          <div class="count">{count} image{"s" if count != 1 else ""}</div>
        </div>"""

    body = f"<h1>Timelapse</h1><div class='grid'>{cards}</div>"
    return page("Timelapse", body)


@app.route("/day/<date>")
def day(date):
    """List hours for a day, with image count per hour."""
    date = str(escape(date))
    day_dir = os.path.join(BASE_DIR, date)
    if not os.path.isdir(day_dir):
        abort(404)

    # Group images by hour
    hours = {}
    for fname in os.listdir(day_dir):
        if fname.endswith(".jpg"):
            # filename: 2026-04-23_14-30.jpg  → hour = "14"
            try:
                hour = fname.split("_")[1].split("-")[0]
                hours.setdefault(hour, 0)
                hours[hour] += 1
            except IndexError:
                pass

    cards = ""
    for hour in sorted(hours.keys()):
        count = hours[hour]
        label = f"{hour}:00 – {hour}:59 UTC"
        cards += f"""
        <div class="card">
          <a href="/day/{escape(date)}/{escape(hour)}">{label}</a>
          <div class="count">{count} image{"s" if count != 1 else ""}</div>
        </div>"""

    breadcrumb = f'<div class="breadcrumb"><a href="/">Timelapse</a> › {escape(date)}</div>'
    body = f"{breadcrumb}<h1>{escape(date)}</h1><div class='grid'>{cards}</div>"
    return page(date, body)


@app.route("/day/<date>/<hour>")
def hour_view(date, hour):
    """Show all images for one hour as a grid."""
    date = str(escape(date))
    hour = str(escape(hour))
    day_dir = os.path.join(BASE_DIR, date)
    if not os.path.isdir(day_dir):
        abort(404)

    images = sorted(
        f for f in os.listdir(day_dir)
        if f.endswith(".jpg") and f.split("_")[1].startswith(hour + "-")
    )

    if not images:
        abort(404)

    grid = ""
    for fname in images:
        minute = fname.split("-")[-1].replace(".jpg", "")
        grid += f"""
        <div>
          <a href="/img/{escape(date)}/{escape(fname)}" target="_blank">
            <img src="/img/{escape(date)}/{escape(fname)}" loading="lazy" alt="{escape(fname)}">
          </a>
          <div class="img-label">{escape(hour)}:{escape(minute)} UTC</div>
        </div>"""

    breadcrumb = (
        f'<div class="breadcrumb">'
        f'<a href="/">Timelapse</a> › '
        f'<a href="/day/{escape(date)}">{escape(date)}</a> › '
        f'{escape(hour)}:00 – {escape(hour)}:59 UTC'
        f'</div>'
    )
    title = f"{date} {hour}:xx UTC"
    body = f"{breadcrumb}<h1>{title}</h1><div class='img-grid'>{grid}</div>"
    return page(title, body)


@app.route("/img/<date>/<filename>")
def serve_image(date, filename):
    """Serve a JPEG from the timelapse directory."""
    date     = str(escape(date))
    filename = str(escape(filename))
    return send_from_directory(os.path.join(BASE_DIR, date), filename)


# --- Upload ------------------------------------------------------------------

@app.route("/upload", methods=["POST"])
def upload():
    folder   = request.headers.get("X-Folder")
    filename = request.headers.get("X-Filename")

    if not folder or not filename:
        log.warning("Missing X-Folder or X-Filename header")
        abort(400, "Missing X-Folder or X-Filename header")

    # Basic validation — prevent path traversal
    if "/" in folder or ".." in folder or "/" in filename or ".." in filename:
        log.warning("Rejected suspicious path: folder=%s filename=%s", folder, filename)
        abort(400, "Invalid folder or filename")

    if not filename.endswith(".jpg"):
        log.warning("Rejected non-JPEG filename: %s", filename)
        abort(400, "Only .jpg files accepted")

    dest_dir  = os.path.join(BASE_DIR, folder)
    dest_path = os.path.join(dest_dir, filename)

    os.makedirs(dest_dir, exist_ok=True)

    # Stream body directly to disk — avoids loading full image in RAM
    with open(dest_path, "wb") as f:
        chunk_size = 8192
        while True:
            chunk = request.stream.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)

    size_kb = os.path.getsize(dest_path) / 1024
    log.info("Saved  %s/%s  (%.1f KB)", folder, filename, size_kb)

    return "OK", 200


# --- Status ------------------------------------------------------------------

@app.route("/status", methods=["GET"])
def status():
    """Quick health check — also reports image count and disk usage."""
    total = 0
    for _, _, files in os.walk(BASE_DIR):
        total += sum(1 for f in files if f.endswith(".jpg"))

    statvfs  = os.statvfs(BASE_DIR)
    free_gb  = (statvfs.f_frsize * statvfs.f_bavail) / (1024 ** 3)
    total_gb = (statvfs.f_frsize * statvfs.f_blocks) / (1024 ** 3)

    return {
        "status":        "ok",
        "images":        total,
        "disk_free_gb":  round(free_gb, 2),
        "disk_total_gb": round(total_gb, 2),
    }, 200


# -----------------------------------------------------------------------------

if __name__ == "__main__":
    os.makedirs(BASE_DIR, exist_ok=True)
    log.info("Timelapse server starting — storing images in %s", BASE_DIR)
    log.info("Listening on %s:%d", HOST, PORT)
    app.run(host=HOST, port=PORT)
