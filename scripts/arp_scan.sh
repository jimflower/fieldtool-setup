#!/usr/bin/env bash
set -euo pipefail
IFACE="${1:-eth0}"
echo "Running arp-scan on $IFACE ..."
if ! command -v arp-scan >/dev/null 2>&1; then
  echo "arp-scan not installed. Try: sudo apt update && sudo apt install -y arp-scan"
  exit 1
fi
sudo arp-scan --interface="$IFACE" --localnet || true
