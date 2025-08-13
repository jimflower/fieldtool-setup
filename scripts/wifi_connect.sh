#!/usr/bin/env bash
set -euo pipefail
if [ -f /opt/fieldtool/config.env ]; then
  set -a
  source /opt/fieldtool/config.env
  set +a
fi

read -rp "SSID [${DEFAULT_SSID:-}]: " SSID
SSID=${SSID:-${DEFAULT_SSID:-}}
read -rsp "PSK (password) [${DEFAULT_PSK:-}]: " PSK; echo
PSK=${PSK:-${DEFAULT_PSK:-}}

if [ -z "${SSID}" ] || [ -z "${PSK}" ]; then
  echo "SSID/PSK cannot be empty."
  exit 1
fi

echo "Connecting $WIFI_IFACE to SSID '$SSID'..."
sudo nmcli dev wifi connect "$SSID" password "$PSK" ifname "${WIFI_IFACE:-wlan0}" || {
  echo "nmcli connect failed. Trying wpa_supplicant fallback..."
  sudo bash -c "wpa_passphrase '$SSID' '$PSK' > /etc/wpa_supplicant/wpa_supplicant.conf"
  sudo wpa_cli -i "${WIFI_IFACE:-wlan0}" reconfigure || true
  sleep 5
}
echo "Done. Current IPs:"
ip -br a
