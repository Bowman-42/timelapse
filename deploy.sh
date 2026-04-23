#!/bin/bash
# Deploy Pi server files — substitutes <username> and <pi-ip> on the fly.
# Source files are never modified, so committing is always safe.
#
# Usage: ./deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/pi.conf"

if [ ! -f "$CONF" ]; then
  echo "Error: pi.conf not found. Copy pi.conf.example and fill in your values."
  exit 1
fi

source "$CONF"

echo "Deploying to $PI_USER@$PI_IP..."

# Substitute <username> in each file and pipe directly to the Pi via SSH
# — source files on disk are never touched

for FILE in pi/server.py pi/timelapse.service; do
  DEST="/home/$PI_USER/timelapse-server/$(basename $FILE)"
  echo "  → $FILE"
  sed "s|<username>|$PI_USER|g" "$SCRIPT_DIR/$FILE" | ssh "$PI_USER@$PI_IP" "cat > $DEST"
done

echo "Reloading systemd and restarting service (you may be prompted for your Pi password)..."
ssh -t "$PI_USER@$PI_IP" "sudo systemctl daemon-reload && sudo systemctl restart timelapse"

echo "Done. Service status:"
ssh "$PI_USER@$PI_IP" "sudo systemctl status timelapse --no-pager -l"
