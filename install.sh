#!/usr/bin/env bash
set -Eeuo pipefail

# ========= defaults (can be overridden via env or ./SECRETS.env) =========
: "${WIFI_COUNTRY:=AU}"
: "${AP_SSID_BASE:=FieldTool}"
: "${AP_PASS:=FieldTool_12345}"                 # 8+ chars
: "${AP_ADDR:=10.99.0.1/24}"
: "${ORBI_SSID:=ORBI13}"
: "${ESPION_SSID:=Espion}"

# Optional secrets file (NOT in git)
if [[ -f "./SECRETS.env" ]]; then
  set -a; . ./SECRETS.env; set +a
fi

# Prompt for PSKs if still unset / placeholder
if [[ -z "${ORBI_PASS:-}" || "${ORBI_PASS:-}" == "REPLACE_ME" ]]; then
  read -rsp "ORBI Wi-Fi password: " ORBI_PASS; echo
fi
if [[ -z "${ESPION_PASS:-}" || "${ESPION_PASS:-}" == "REPLACE_ME" ]]; then
  read -rsp "Espion (Beryl) Wi-Fi password: " ESPION_PASS; echo
fi

echo "[INFO] Installing base packages…"
sudo apt-get update -y
sudo apt-get install -y \
  network-manager nmap arp-scan tcpdump dnsmasq nftables ethtool \
  minicom picocom screen autossh ipcalc sipcalc jq iperf3

# Region + radios
sudo rfkill unblock wifi || true
sudo raspi-config nonint do_wifi_country "$WIFI_COUNTRY" 2>/dev/null || true
sudo iw reg set "$WIFI_COUNTRY" || true

# ========= install FieldTool files =========
sudo install -d -m755 /opt/fieldtool/scripts
sudo rsync -a --chmod=Du=rwx,Fu=rwX ./scripts/ /opt/fieldtool/scripts/
if [[ -f ./scripts/fieldtool ]]; then
  sudo install -m0755 ./scripts/fieldtool /usr/local/bin/fieldtool
fi

# Polkit (optional)
if [[ -d ./polkit ]]; then
  sudo install -d -m755 /etc/polkit-1/rules.d
  for f in ./polkit/*.rules; do
    [[ -e "$f" ]] && sudo install -m0644 "$f" /etc/polkit-1/rules.d/
  done
fi

# Systemd (optional)
if [[ -d ./systemd ]]; then
  for f in ./systemd/*; do
    [[ -e "$f" ]] && sudo install -m0644 "$f" /etc/systemd/system/
  done
  sudo systemctl daemon-reload
  # AP DHCP unit (our dedicated dnsmasq); disable global dnsmasq to avoid conflicts
  sudo systemctl disable --now dnsmasq 2>/dev/null || true
  sudo systemctl enable --now ap-dhcp.service 2>/dev/null || true
  sudo systemctl enable --now fieldtool-ap-heal.timer 2>/dev/null || true
fi

# ========= /opt/fieldtool/config.env bootstrap =========
LAN_CAND=$(ip -o link | awk -F': ' '/eth|enx|usb/{print $2}' | head -n1)
AP_IF="${AP_IF:-wlan0}"
LAN_IF="${LAN_IF:-${LAN_CAND:-eth0}}"
WLAN1_IF="${WLAN1_IF:-wlan1}"

sudo install -d -m755 /opt/fieldtool
if [[ ! -f /opt/fieldtool/config.env ]]; then
  sudo tee /opt/fieldtool/config.env >/dev/null <<EOF
AP_IF="$AP_IF"
LAN_IF="$LAN_IF"
WLAN1_IF="$WLAN1_IF"
AP_ADDR="$AP_ADDR"
AP_NET="$(ipcalc -n "$AP_ADDR" | awk '/Network:/{print $2}')"
AP_GW="${AP_ADDR%/*}"
DNS_SERVERS="1.1.1.1,8.8.8.8"

DEFAULT_SCAN_IF="\$LAN_IF"
NMAP_PING_OPTS="-sn"
ARP_SCAN_OPTS="--retry=3 --timeout=200"

SERIAL_BAUD_XL1000="115200"
XL1000_TTY_GLOB="/dev/serial/by-id/*FTDI*if00*"

BRIDGE_IN_IF="\$AP_IF"
BRIDGE_OUT_IF="\$LAN_IF"
EOF
fi

# ensure scripts source config.env (idempotent)
for f in /opt/fieldtool/scripts/*; do
  grep -q '/opt/fieldtool/config.env' "$f" || \
  sudo sed -i '1a [ -f /opt/fieldtool/config.env ] && . /opt/fieldtool/config.env || true' "$f"
done

# ========= AP-first on wlan0 (no NM restart; safe for SSH) =========
sudo nmcli radio wifi on || true
sudo nmcli dev set "$LAN_IF" managed no || true   # keep NM off our wired aliases

# Unique SSID with MAC suffix
MAC=$(tr -d : </sys/class/net/"$AP_IF"/address 2>/dev/null || echo 000000)
SSID="${AP_SSID_BASE}-${MAC: -6}"

sudo nmcli con delete fieldtool-ap 2>/dev/null || true
sudo nmcli con add type wifi ifname "$AP_IF" con-name fieldtool-ap ssid "$SSID" >/dev/null
sudo nmcli con mod fieldtool-ap \
  802-11-wireless.mode ap 802-11-wireless.band bg 802-11-wireless.channel 6 \
  802-11-wireless.powersave 2 802-11-wireless.hidden no \
  ipv4.method manual ipv4.addresses "$AP_ADDR" ipv6.method disabled \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$AP_PASS"
sudo iw dev "$AP_IF" set power_save off || true
sudo nmcli con up fieldtool-ap || true

# ========= Best-effort uplink profiles on wlan1 (do NOT break SSH) =========
try_uplink () {
  local ssid="$1" psk="$2" ifc="$3" prio="$4"
  [[ -z "$ssid" ]] && return 0
  sudo nmcli dev wifi rescan ifname "$ifc" || true
  sudo nmcli con delete "$ssid" 2>/dev/null || true
  sudo nmcli con add type wifi ifname "$ifc" con-name "$ssid" ssid "$ssid" >/dev/null
  [[ -n "$psk" ]] && sudo nmcli con mod "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk"
  sudo nmcli con mod "$ssid" connection.autoconnect yes connection.autoconnect-priority "$prio" ipv4.route-metric 50 ipv6.route-metric 50
}
try_uplink "$ORBI_SSID"   "${ORBI_PASS:-}"   "$WLAN1_IF" 200
try_uplink "$ESPION_SSID" "${ESPION_PASS:-}" "$WLAN1_IF" 100

echo
echo "[OK] Install complete."
echo "AP: SSID=${SSID}  PASS=${AP_PASS}  IP=${AP_ADDR%/*}"
echo "Wired iface unmanaged: ${LAN_IF}"
echo "Uplink profiles staged on ${WLAN1_IF}: ${ORBI_SSID}, ${ESPION_SSID}"
echo
echo "Tip: run 'fieldtool' for the menu. Menu 9 (watch-boot) + 17 (auto-bridge) are in this build."
