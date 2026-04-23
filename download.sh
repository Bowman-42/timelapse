#!/bin/bash
# Download images from Pi to Mac and remove them from the Pi.
# Uses rsync --remove-source-files: each file is deleted from the Pi
# only after it has been successfully transferred.
#
# Usage: ./download.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/pi.conf"

if [ ! -f "$CONF" ]; then
  echo "Error: pi.conf not found. Copy pi.conf.example and fill in your values."
  exit 1
fi

source "$CONF"

LOCAL_DIR="$HOME/timelapse"
REMOTE_DIR="/home/$PI_USER/timelapse"

echo "Download timelapse images from $PI_USER@$PI_IP"
echo "  Remote: $REMOTE_DIR"
echo "  Local:  $LOCAL_DIR"
echo ""
echo "Files will be DELETED from the Pi after successful transfer."
read -p "Continue? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
mkdir -p "$LOCAL_DIR"

# Transfer and remove source files as they are confirmed received
rsync -av --progress --remove-source-files \
  "$PI_USER@$PI_IP:$REMOTE_DIR/" "$LOCAL_DIR/"

# Remove empty date directories left behind on the Pi
echo "Cleaning up empty directories on Pi..."
ssh "$PI_USER@$PI_IP" "find $REMOTE_DIR -mindepth 1 -type d -empty -delete 2>/dev/null || true"

echo ""
echo "Done. Images saved to $LOCAL_DIR"
