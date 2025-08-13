#!/usr/bin/env bash
set -euo pipefail
if [ -f /opt/fieldtool/config.env ]; then
  set -a
  source /opt/fieldtool/config.env
  set +a
fi
DEV="${SERIAL_DEVICE:-/dev/ttyUSB0}"
BAUD="${SERIAL_BAUD:-9600}"
echo "Opening serial console on $DEV @ $BAUD. Exit with Ctrl-A then K then Y."
if ! command -v screen >/dev/null 2>&1; then
  echo "screen not installed. Installing..."
  sudo apt update && sudo apt install -y screen
fi
sudo screen "$DEV" "$BAUD"
