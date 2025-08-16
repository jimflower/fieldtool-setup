#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# ----- defaults -----
: "${WIFI_COUNTRY:=AU}"
: "${AP_SSID_BASE:=FieldTool}"
: "${AP_PASS:=FieldTool_12345}"
: "${AP_IF:=wlan0}"
: "${WLAN1_IF:=wlan1}"
: "${ORBI_SSID:=ORBI13}"
: "${ESPION_SSID:=Espion}"

# Optional secrets file (not committed)
set -a
[ -f ./SECRETS.env ] && . ./SECRETS.env
set +a

# Prompt for secrets if still unset
if [ -z "${ORBI_PASS:-}" ] || [ "${ORBI_PASS:-}" = "REPLACE_ME" ]; then
  read -rsp "ORBI Wi-Fi password: " ORBI_PASS; echo
fi
if [ -z "${ESPION_PASS:-}" ] || [ "${ESPION_PASS:-}" = "REPLACE_ME" ]; then
  read -rsp "Espion (Beryl) Wi-Fi password: " ESPION_PASS; echo
fi

echo "[INFO] Installing packages…"
sudo apt-get update
sudo apt-get install -y \
  network-manager git nmap arp-scan tcpdump dnsmasq nftables \
  minicom screen picocom autossh ethtool

# Country / RF
sudo rfkill unblock wifi || true
sudo raspi-config nonint do_wifi_country "${WIFI_COUNTRY}" || true
sudo iw reg set "${WIFI_COUNTRY}" || true

# Runtime dir each boot
sudo tee /etc/tmpfiles.d/fieldtool.conf >/dev/null <<'TMP'
d /run/fieldtool 0755 root root -
TMP
sudo systemd-tmpfiles --create /etc/tmpfiles.d/fieldtool.conf

# Install scripts + launcher
sudo install -d -m755 /opt/fieldtool/scripts
sudo rsync -a --chmod=Du=rwx,Fu=rwX ./scripts/ /opt/fieldtool/scripts/ || true
if [ -f ./scripts/fieldtool ]; then
  sudo install -m0755 ./scripts/fieldtool /usr/local/bin/fieldtool
fi

# Ensure all scripts optionally source config.env
for f in /opt/fieldtool/scripts/*; do
  grep -q '/opt/fieldtool/config.env' "$f" || \
    sudo sed -i '1a [ -f /opt/fieldtool/config\.env ] && . /opt/fieldtool/config\.env || true' "$f"
done

# Create config.env with sensible defaults
LAN_CAND=$(ip -o link | awk -F': ' '/eth|enx|usb/{print $2}' | head -n1)
: "${LAN_IF:=${LAN_CAND:-eth0}}"
sudo install -d -m755 /opt/fieldtool
if [ ! -f /opt/fieldtool/config.env ]; then
sudo tee /opt/fieldtool/config.env >/dev/null <<CFG
AP_IF="${AP_IF}"
LAN_IF="${LAN_IF}"
WLAN1_IF="${WLAN1_IF}"
AP_ADDR="10.99.0.1/24"
AP_NET="10.99.0.0/24"
AP_GW="10.99.0.1"
DNS_SERVERS="1.1.1.1,8.8.8.8"
DEFAULT_SCAN_IF="${LAN_IF}"
NMAP_PING_OPTS="-sn"
ARP_SCAN_OPTS="--retry=3 --timeout=200"
SERIAL_BAUD_XL1000="115200"
XL1000_TTY_GLOB="/dev/serial/by-id/*FTDI*if00*"
BRIDGE_IN_IF="${AP_IF}"
BRIDGE_OUT_IF="${LAN_IF}"
CFG
fi

# AP hardening (no powersave, no MAC randomization)
sudo tee /etc/NetworkManager/conf.d/wifi-powersave.conf >/dev/null <<'NMPS'
[connection]
wifi.powersave=2
NMPS
sudo systemctl restart NetworkManager || true
sudo nmcli radio wifi on || true

# Build AP SSID based on wlan0 MAC
MAC=$(tr -d : </sys/class/net/"${AP_IF}"/address 2>/dev/null || echo 000000)
SSID="${AP_SSID_BASE}-${MAC: -6}"

# Create/replace AP, force it onto wlan0 FIRST
sudo nmcli con delete fieldtool-ap 2>/dev/null || true
sudo nmcli con add type wifi ifname "${AP_IF}" con-name fieldtool-ap ssid "${SSID}" 802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 11
sudo nmcli con mod fieldtool-ap \
  802-11-wireless.powersave 2 \
  802-11-wireless.mac-address-randomization 0 802-11-wireless.cloned-mac-address permanent \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${AP_PASS}" \
  ipv4.method manual ipv4.addresses 10.99.0.1/24 ipv6.method disabled \
  connection.interface-name "${AP_IF}" connection.autoconnect yes connection.autoconnect-priority 900

# Kick any client on wlan0 and bring AP up
sudo nmcli dev disconnect "${AP_IF}" || true
sudo nmcli con up fieldtool-ap || true
sudo iw dev "${AP_IF}" set power_save off || true

# AP DHCP (wlan0 only) — install config + foreground unit
sudo install -d -m755 /etc/fieldtool /var/lib/fieldtool
if [ ! -f /etc/fieldtool/ap-dhcp.conf ]; then
sudo tee /etc/fieldtool/ap-dhcp.conf >/dev/null <<'DNS'
interface=wlan0
bind-interfaces
no-resolv
port=0
dhcp-range=10.99.0.50,10.99.0.150,255.255.255.0,12h
dhcp-option=3,10.99.0.1
dhcp-option=6,1.1.1.1
dhcp-leasefile=/var/lib/fieldtool/ap.leases
log-dhcp
DNS
fi
sudo tee /etc/systemd/system/ap-dhcp.service >/dev/null <<'UNIT'
[Unit]
Description=FieldTool AP DHCP (wlan0)
After=NetworkManager.service
Requires=NetworkManager.service
Conflicts=dnsmasq.service

[Service]
ExecStart=/usr/sbin/dnsmasq -k -C /etc/fieldtool/ap-dhcp.conf
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl disable --now dnsmasq 2>/dev/null || true
sudo systemctl enable --now ap-dhcp

# Ensure AP is reclaimed on boot
sudo tee /etc/systemd/system/fieldtool-claim-wlan0.service >/dev/null <<'CLAIM'
[Unit]
Description=Ensure FieldTool AP owns wlan0
After=NetworkManager.service
Requires=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli dev disconnect wlan0
ExecStart=/usr/bin/nmcli con up fieldtool-ap
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CLAIM
sudo systemctl daemon-reload
sudo systemctl enable --now fieldtool-claim-wlan0.service

# Best-effort uplink helper (wlan1 only)
try_uplink() {
  local ssid="$1" pass="$2" ifname="${3:-$WLAN1_IF}"
  [ -z "$ssid" ] && return 0
  if ! ip link show "$ifname" &>/dev/null; then
    echo "[WARN] $ifname not present; skipping uplink '$ssid'."
    return 0
  fi
  sudo nmcli dev wifi rescan ifname "$ifname" || true
  if sudo nmcli -f SSID dev wifi list ifname "$ifname" | awk 'NR>1' | grep -Fxq "$ssid"; then
    sudo nmcli con delete "$ssid" 2>/dev/null || true
    sudo nmcli con add type wifi ifname "$ifname" con-name "$ssid" ssid "$ssid" || true
    [ -n "$pass" ] && sudo nmcli con mod "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pass" || true
    sudo nmcli con mod "$ssid" connection.interface-name "$ifname" connection.autoconnect yes connection.autoconnect-priority 100 ipv4.route-metric 50 ipv6.route-metric 50 || true
    echo "[OK] Uplink '$ssid' configured on $ifname."
  else
    echo "[WARN] SSID '$ssid' not seen on $ifname now; will not block AP."
  fi
}

# Disable autoconnect for any other wlan0 client profiles (don’t steal AP)
for NAME in $(nmcli -t -f NAME,DEVICE con show | awk -F: -v ifc="${AP_IF}" '$2==ifc{print $1}'); do
  [ "$NAME" = "fieldtool-ap" ] || sudo nmcli con mod "$NAME" connection.autoconnect no
done

# Try uplinks on wlan1 (non-fatal)
try_uplink "${ORBI_SSID:-}"   "${ORBI_PASS:-}"   "${WLAN1_IF}"
try_uplink "${ESPION_SSID:-}" "${ESPION_PASS:-}" "${WLAN1_IF}"

echo "[OK] Install complete."
echo "AP SSID: ${SSID}  pass: ${AP_PASS}  IP: 10.99.0.1"
