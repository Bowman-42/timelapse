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
from flask import Flask, request, abort

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
        "status":      "ok",
        "images":      total,
        "disk_free_gb": round(free_gb, 2),
        "disk_total_gb": round(total_gb, 2),
    }, 200


if __name__ == "__main__":
    os.makedirs(BASE_DIR, exist_ok=True)
    log.info("Timelapse server starting — storing images in %s", BASE_DIR)
    log.info("Listening on %s:%d", HOST, PORT)
    app.run(host=HOST, port=PORT)
