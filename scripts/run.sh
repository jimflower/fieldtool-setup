#!/usr/bin/env bash
set -euo pipefail

cd /opt/fieldtool

# Load optional env vars
if [ -f config.env ]; then
  set -a
  # shellcheck disable=SC1091
  source config.env
  set +a
fi

# Activate venv
# shellcheck disable=SC1091
source .venv/bin/activate

# If FIELDAPP is set, use it, else auto-pick a reasonable entry
APP="${FIELDAPP:-}"
if [ -z "$APP" ]; then
  for cand in /opt/fieldtool/app/main.py /opt/fieldtool/fieldtool/app.py /opt/fieldtool/app.py /opt/fieldtool/run.py; do
    if [ -f "$cand" ]; then APP="$cand"; break; fi
  done
fi

if [ -z "$APP" ]; then
  echo "ERROR: No entrypoint found. Set FIELDAPP in /opt/fieldtool/config.env"
  exit 1
fi

echo "Starting: python $APP"
exec python "$APP"
