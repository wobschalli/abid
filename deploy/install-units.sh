#!/usr/bin/env bash
# (Re)install the two systemd units from the repo and restart them. For when
# the checkout moved or a unit file changed — everything else the full
# installer does is already in place. Run as root from the repo:
#
#   sudo bash deploy/install-units.sh
set -euo pipefail
APP_USER=alan
APP_DIR=$(cd "$(dirname "$0")/.." && pwd)

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ "$(stat -c %U "$APP_DIR")" = "$APP_USER" ] || chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

for unit in abid-web abid-bot; do
  # The unit files name the canonical path; substitute if this checkout lives elsewhere.
  sed "s|/opt/abid|$APP_DIR|g" "$APP_DIR/deploy/$unit.service" > "/etc/systemd/system/$unit.service"
done
systemctl daemon-reload
systemctl enable abid-web abid-bot >/dev/null
systemctl restart abid-web
systemctl restart abid-bot
sleep 6
for unit in abid-web abid-bot; do printf "%-9s %s  (%s)\n" "$unit" "$(systemctl is-active $unit)" "$(systemctl show -p WorkingDirectory --value $unit)"; done
