#!/usr/bin/env bash
[ -f /opt/fieldtool/config.env ] && . /opt/fieldtool/config.env || true
set -euo pipefail
sudo rm -f /usr/local/bin/fieldtool
sudo rm -rf /opt/fieldtool
echo "✅ Uninstalled Field Tool scripts."
