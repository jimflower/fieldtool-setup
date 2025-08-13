#!/usr/bin/env bash
set -euo pipefail
# Install scripts-only Field Tool

# Packages needed
sudo apt update
sudo apt install -y arp-scan network-manager screen

# Deploy
sudo mkdir -p /opt/fieldtool/scripts
sudo cp -r ../scripts /opt/fieldtool/
sudo cp ../config.env /opt/fieldtool/config.env

# Make menu runner accessible as 'fieldtool'
sudo tee /usr/local/bin/fieldtool >/dev/null <<'EOF'
#!/usr/bin/env bash
exec /opt/fieldtool/scripts/menu.sh
EOF
sudo chmod +x /usr/local/bin/fieldtool

echo "✅ Installed. Run: fieldtool"
