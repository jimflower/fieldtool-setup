#!/usr/bin/env bash
set -euo pipefail
: "${WIFI_COUNTRY:=AU}"
: "${AP_SSID_BASE:=FieldTool}"
: "${AP_PASS:=FieldTool_12345}"
: "${ORBI_SSID:=ORBI13}";   : "${ORBI_PASS:=REPLACE_ME}"
: "${ESPION_SSID:=Espion}"; : "${ESPION_PASS:=REPLACE_ME}"

sudo apt-get update
sudo apt-get install -y network-manager git nmap arp-scan tcpdump dnsmasq nftables autossh minicom screen picocom

sudo rfkill unblock wifi || true
sudo raspi-config nonint do_wifi_country "$WIFI_COUNTRY" || true
sudo iw reg set "$WIFI_COUNTRY" || true

sudo install -d -m755 /opt/fieldtool/scripts
sudo rsync -a --chmod=Du=rwx,Fu=rwX ./scripts/ /opt/fieldtool/scripts/
[ -f ./scripts/fieldtool ] && sudo install -m0755 ./scripts/fieldtool /usr/local/bin/fieldtool

# Polkit (optional)
[ -f ./polkit/10-nm-wlan1.rules ] && { sudo install -m0644 ./polkit/10-nm-wlan1.rules /etc/polkit-1/rules.d/10-nm-wlan1.rules; sudo systemctl restart polkit || true; }

# Systemd (optional)
if [ -d ./systemd ]; then
  for f in ./systemd/*; do sudo install -m0644 "$f" "/etc/systemd/system/$(basename "$f")"; done
  sudo systemctl daemon-reload
  sudo systemctl enable --now fieldtool-ap-heal.timer 2>/dev/null || true
fi

# Recreate AP on wlan0
MAC=$(tr -d : </sys/class/net/wlan0/address 2>/dev/null || echo 000000)
SSID="${AP_SSID_BASE}-${MAC: -6}"
sudo nmcli radio wifi on
sudo nmcli con delete fieldtool-ap 2>/dev/null || true
sudo nmcli con add type wifi ifname wlan0 con-name fieldtool-ap ssid "$SSID" 802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6
sudo nmcli con mod fieldtool-ap wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$AP_PASS" ipv4.method shared ipv4.addresses 10.99.0.1/24 ipv4.never-default yes connection.autoconnect yes connection.autoconnect-priority 100
sudo nmcli con up fieldtool-ap || true

# Home/field on wlan1
[ "$ORBI_PASS"   != "REPLACE_ME" ] && sudo nmcli dev wifi connect "$ORBI_SSID"  ifname wlan1 name "$ORBI_SSID"  password "$ORBI_PASS"  || true
[ "$ESPION_PASS" != "REPLACE_ME" ] && sudo nmcli dev wifi connect "$ESPION_SSID" ifname wlan1 name "$ESPION_SSID" password "$ESPION_PASS" || true
sudo nmcli con mod "$ORBI_SSID"  connection.interface-name wlan1 connection.autoconnect yes connection.autoconnect-priority 200 ipv4.route-metric 50 ipv6.route-metric 50 2>/dev/null || true
sudo nmcli con mod "$ESPION_SSID" connection.interface-name wlan1 connection.autoconnect yes connection.autoconnect-priority 100 ipv4.route-metric 50 ipv6.route-metric 50 2>/dev/null || true

echo "[OK] Install complete."
echo "AP SSID: $SSID (pass: $AP_PASS) IP: 10.99.0.1"
