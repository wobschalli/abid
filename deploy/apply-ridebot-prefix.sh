#!/usr/bin/env bash
# Move the live dashboard from the domain root to /ridebot/. Run ONCE as root:
#
#   sudo bash deploy/apply-ridebot-prefix.sh
#
# Patches the certbot-managed nginx site in place (certbot's TLS lines are
# untouched), sets ABID_ROOT_PATH in /etc/abid/env, and restarts the web
# service. Idempotent.
set -euo pipefail
SITE=/etc/nginx/sites-available/abid
ENV_FILE=/etc/abid/env
PREFIX=/ridebot

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$SITE" ] || { echo "no nginx site at $SITE"; exit 1; }

echo "== nginx: route $PREFIX/ to the app"
cp -n "$SITE" "$SITE.before-ridebot" || true
python3 - "$SITE" "$PREFIX" <<'PY'
import re, sys
site, prefix = sys.argv[1], sys.argv[2]
s = open(site).read()
if f"location {prefix}/ " not in s:
    # the app block: `location / {` -> `location /ridebot/ {`
    s = re.sub(r"\n(\s*)location / \{", f"\n\\1location {prefix}/ {{", s, count=1)
    # the static-asset block only makes sense under the prefix now
    s = s.replace("location ~* \\.(css|js|webp|png|ico)$ {", f"location ~* ^{prefix}/.*\\.(css|js|webp|png|ico)$ {{")
    # root and bare-prefix redirects, placed before the app block
    s = s.replace(f"    location {prefix}/ {{",
                  f"    location = / {{ return 302 {prefix}/; }}\n"
                  f"    location = {prefix} {{ return 301 {prefix}/; }}\n\n"
                  f"    location {prefix}/ {{", 1)
    open(site, "w").write(s)
    print("   patched")
else:
    print("   already routed")
PY
nginx -t -q && systemctl reload nginx && echo "   nginx reloaded"

echo "== app: ABID_ROOT_PATH=$PREFIX"
if grep -q '^ABID_ROOT_PATH=' "$ENV_FILE"; then
  sed -i "s|^ABID_ROOT_PATH=.*|ABID_ROOT_PATH=$PREFIX|" "$ENV_FILE"
else
  printf '\n# Mounted under this prefix; nginx routes it. Empty = domain root.\nABID_ROOT_PATH=%s\n' "$PREFIX" >> "$ENV_FILE"
fi
systemctl restart abid-web && sleep 4 && systemctl is-active abid-web
echo "done: https://$(grep -m1 server_name "$SITE" | awk '{print $2}' | tr -d ';')$PREFIX/"
