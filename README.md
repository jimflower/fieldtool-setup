# FieldTool Setup (Backup + One-Hit Installer)

This repository installs your FieldTool environment on a fresh Raspberry Pi:
- `/opt/fieldtool/scripts` + `/usr/local/bin/fieldtool` menu
- Wi-Fi **AP on wlan0** (10.99.0.1/24)
- Home/Field uplink profiles on **wlan1**
- Optional helpers (polkit rule, services) if present in the repo

> **Passwords are never stored in git.** The installer prompts for Wi-Fi secrets or reads them from a local `SECRETS.env` that is **.gitignored**.

---

## Quick Restore (recommended: prompt for secrets)

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/jimflower/fieldtool-setup.git fieldtool-setup
cd fieldtool-setup
sudo ./install.sh


