# FieldTool Setup (Backup + One-Hit Installer)
Restore on a fresh Pi:
  sudo apt-get update && sudo apt-get install -y git
  git clone https://github.com/<YOUR_USER>/<YOUR_REPO>.git fieldtool-setup
  cd fieldtool-setup
  sudo bash ./install.sh ORBI_PASS="<home pass>" ESPION_PASS="!Matrix565"
(NM profiles have PSKs scrubbed: look for REPLACE_ME.)
