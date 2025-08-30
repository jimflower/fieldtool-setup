#!/usr/bin/env bash
[ -f /opt/fieldtool/config.env ] && . /opt/fieldtool/config.env || true
set -euo pipefail
TS=$(date +"%Y-%m-%d_%H%M")
OUT="${HOME}/fieldtool_backup_${TS}.tgz"
echo "Creating backup: $OUT"
sudo tar -czf "$OUT" \
  --exclude="/opt/fieldtool/.venv" \
  --exclude="/opt/fieldtool/__pycache__" \
  -C / opt/fieldtool
echo "✅ Backup saved to $OUT"
