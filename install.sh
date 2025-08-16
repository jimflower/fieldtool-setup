#!/usr/bin/env bash
shopt -s nullglob
set -euo pipefail
# ----- config defaults -----
: "${WIFI_COUNTRY:=AU}"
: "${AP_SSID_BASE:=FieldTool}"
: "${AP_PASS:=FieldTool_12345}"
: "${ORBI_SSID:=ORBI13}"
: "${ESPION_SSID:=Espion}"

# Optional secrets file (NOT committed): ./SECRETS.env
# Example contents:
# ORBI_PASS='your-home-pass'
# ESPION_PASS='your-espion-pass'
set -a
[ -f "./SECRETS.env" ] && . "./SECRETS.env"
set +a

# Prompt for secrets if still unset/placeholder
if [ -z "${ORBI_PASS:-}" ] || [ "${ORBI_PASS}" = "REPLACE_ME" ]; then
  read -rsp "ORBI Wi-Fi password: " ORBI_PASS; echo
fi
if [ -z "${ESPION_PASS:-}" ] || [ "${ESPION_PASS}" = "REPLACE_ME" ]; then
  read -rsp "Espion (Beryl) Wi-Fi password: " ESPION_PASS; echo
fi

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
  for f in ./systemd/*; do [ -e "$f" ] || continue; sudo install -m0644 "$f" "/etc/systemd/system/$(basename "$f")"; done
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
# --- BEGIN FieldTool bootstrap additions ---

# Create /opt/fieldtool/config.env with sensible defaults if missing
LAN_CAND=$(ip -o link | awk -F': ' '/eth|enx|usb/{print $2}' | head -n1)
: "${AP_IF:=wlan0}"
: "${LAN_IF:=${LAN_CAND:-eth0}}"
: "${WLAN1_IF:=wlan1}"
sudo install -d -m 755 /opt/fieldtool
if [ ! -f /opt/fieldtool/config.env ]; then
sudo tee /opt/fieldtool/config.env >/dev/null <<EOF_CFG
AP_IF="$AP_IF"
LAN_IF="$LAN_IF"
WLAN1_IF="$WLAN1_IF"
AP_ADDR="10.99.0.1/24"
AP_NET="10.99.0.0/24"
AP_GW="10.99.0.1"
DNS_SERVERS="1.1.1.1,8.8.8.8"
DEFAULT_SCAN_IF="$LAN_IF"
NMAP_PING_OPTS="-sn"
ARP_SCAN_OPTS="--retry=3 --timeout=200"
SERIAL_BAUD_XL1000="115200"
XL1000_TTY_GLOB="/dev/serial/by-id/*FTDI*if00*"
BRIDGE_IN_IF="$AP_IF"
BRIDGE_OUT_IF="$LAN_IF"
EOF_CFG
fi

# Ensure all scripts optionally source config.env (no-crash if absent)
sudo rsync -a --chmod=Du=rwx,Fu=rwX ./scripts/ /opt/fieldtool/scripts/
for f in /opt/fieldtool/scripts/*; do
  grep -q '/opt/fieldtool/config.env' "$f" || \
  sudo sed -i '1a [ -f /opt/fieldtool/config\.env ] && . /opt/fieldtool/config\.env || true' "$f"
done

# Harden AP profile on wlan0
sudo nmcli radio wifi on
sudo nmcli con delete fieldtool-ap 2>/dev/null || true
MAC=$(tr -d : </sys/class/net/"$AP_IF"/address 2>/dev/null || echo 000000)
SSID="${AP_SSID_BASE:-FieldTool}-${MAC: -6}"
sudo nmcli con add type wifi ifname "$AP_IF" con-name fieldtool-ap ssid "$SSID" 802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 11
sudo nmcli con mod fieldtool-ap \
  802-11-wireless.powersave 2 \
  802-11-wireless.mac-address-randomization 0 802-11-wireless.cloned-mac-address permanent \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${AP_PASS:-FieldTool_12345}" \
  ipv4.method manual ipv4.addresses 10.99.0.1/24 ipv6.method disabled
sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null <<'EOF_PS'
[connection]
wifi.powersave=2
EOF_PS
sudo systemctl restart NetworkManager || true
sudo iw dev "$AP_IF" set power_save off || true
sudo nmcli con up fieldtool-ap || true

# Install AP DHCP (wlan0-only) and disable the global dnsmasq unit to avoid conflicts
sudo install -d -m755 /etc/fieldtool /var/lib/fieldtool
[ -f /etc/fieldtool/ap-dhcp.conf ] || sudo cp ./configs/ap-dhcp.conf /etc/fieldtool/ap-dhcp.conf
sudo install -m0644 ./systemd/ap-dhcp.service /etc/systemd/system/ap-dhcp.service
sudo systemctl daemon-reload
sudo systemctl disable --now dnsmasq 2>/dev/null || true
sudo systemctl enable --now ap-dhcp

echo "[OK] AP ready on $AP_IF → SSID: $SSID (pass: ${AP_PASS:-FieldTool_12345}) IP: 10.99.0.1"
# --- END FieldTool bootstrap additions ---
