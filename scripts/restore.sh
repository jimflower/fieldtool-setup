#!/usr/bin/env bash
set -euo pipefail
TGZ="${1:-}"
if [ -z "$TGZ" ]; then
  echo "Usage: restore.sh </path/to/backup.tgz>"
  exit 1
fi
echo "Restoring from $TGZ ..."
TMP=$(mktemp -d)
tar -xzf "$TGZ" -C "$TMP"
SRC=""
if [ -d "$TMP/opt/fieldtool" ]; then
  SRC="$TMP/opt/fieldtool"
elif [ -d "$TMP/fieldtool" ]; then
  SRC="$TMP/fieldtool"
else
  echo "Could not find fieldtool folder in backup. Inspect $TMP"
  exit 1
fi
sudo rsync -a "$SRC/" /opt/fieldtool/
sudo chown -R $USER:$USER /opt/fieldtool
echo "✅ Restore complete."
