#!/usr/bin/env bash
set -euo pipefail
cd /opt/fieldtool

if [ -f config.env ]; then
  set -a
  source config.env
  set +a
fi

# Menu loop
while true; do
  clear
  echo "==================== Field Tool (CLI) ===================="
  echo "Host: $(hostname)    IP: $(hostname -I | awk '{print $1}')"
  echo "Config: /opt/fieldtool/config.env"
  echo "----------------------------------------------------------"
  echo " 1) Wi-Fi: connect to SSID"
  echo " 2) Network: ARP scan (eth0)"
  echo " 3) Network: ARP scan (wlan1)"
  echo " 4) Serial console (screen)"
  echo " 5) Backup /opt/fieldtool to ~/fieldtool_backup_<ts>.tgz"
  echo " 6) Restore from backup .tgz"
  echo " 7) Show system info"
  echo " q) Quit"
  echo "----------------------------------------------------------"
  read -rp "Choose an option: " CH
  case "$CH" in
    1) /opt/fieldtool/scripts/wifi_connect.sh ; read -rp 'Press Enter...' ;;
    2) /opt/fieldtool/scripts/arp_scan.sh "$ETH_IFACE" ; read -rp 'Press Enter...' ;;
    3) /opt/fieldtool/scripts/arp_scan.sh "$WIFI_IFACE" ; read -rp 'Press Enter...' ;;
    4) /opt/fieldtool/scripts/serial_console.sh ;;
    5) /opt/fieldtool/scripts/backup.sh ; read -rp 'Press Enter...' ;;
    6) read -rp "Path to backup .tgz: " P; /opt/fieldtool/scripts/restore.sh "$P" ; read -rp 'Press Enter...' ;;
    7) echo "Kernel: $(uname -a)"; echo; ip -br a; echo; df -h; echo; free -h; read -rp 'Press Enter...' ;;
    q|Q) exit 0 ;;
    *) echo "Invalid choice"; sleep 1 ;;
  esac
done
