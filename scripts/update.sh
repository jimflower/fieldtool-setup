#!/usr/bin/env bash
set -euo pipefail
cd /opt/fieldtool
# If this repo was deployed via rsync or tar, you can overlay updates by copying new files here first.
# Then reinstall deps (if requirements changed) and restart.
source .venv/bin/activate
pip install --upgrade pip
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi
deactivate
sudo systemctl restart fieldtool
sudo systemctl status --no-pager fieldtool || true
echo "✅ Update complete."
