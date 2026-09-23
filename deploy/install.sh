#!/usr/bin/env bash
# Server setup and reconciliation for Ubuntu 24.04. Run as root from the repo:
#
#   sudo bash deploy/install.sh abidepurdue.com
#
# Idempotent — re-running is how anything gets fixed. Layout it produces:
#   /opt/abid            the checkout, owned by the `abid` service account
#   /opt/ruby/3.3.8      Ruby, system-wide (the version the app is tested on;
#                        Ubuntu's 3.2 makes bundler pick an older or-tools)
#   /etc/abid/env        secrets and settings, root:abid 640
#   abid-web, abid-bot   systemd units running as `abid`
#   nginx                TLS via certbot; the app served under /abidebot/
# The human operator (OPERATOR, default alan) gets passwordless systemctl and
# journalctl for the two units, and nothing else.
#
# On a 1-core, 2GB box the first run takes 30-45 minutes: Ruby compiles, and
# or-tools' C++ extension needs the swapfile below. Later runs take seconds.
set -euo pipefail

APP_USER=${APP_USER:-abid}
OPERATOR=${OPERATOR:-alan}
APP_DIR=${APP_DIR:-/opt/abid}
PREFIX=${PREFIX:-/abidebot}
HOSTNAME_ARG=${1:-}
ENV_FILE=/etc/abid/env
RUBY_VERSION=3.3.8
RUBY_DIR=/opt/ruby/$RUBY_VERSION
BUNDLER_VERSION=2.6.9
BUNDLE=$RUBY_DIR/bin/bundle
SITE=/etc/nginx/sites-available/abid

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$APP_DIR/Gemfile" ] || { echo "no app at $APP_DIR"; exit 1; }

echo "== service account $APP_USER"
id "$APP_USER" >/dev/null 2>&1 || useradd --system --home-dir "/home/$APP_USER" --create-home --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "/home/$APP_USER"; chown "$APP_USER":"$APP_USER" "/home/$APP_USER"
# The services run as $APP_USER and git pull / bundle / tmp writes happen as
# them, so the checkout has to be theirs.
[ "$(stat -c %U "$APP_DIR")" = "$APP_USER" ] || chown -R "$APP_USER":"$APP_USER" "$APP_DIR"
# The token lives in here; nobody but the app user may read it.
[ -f "$APP_DIR/config.yml" ] && chmod 600 "$APP_DIR/config.yml"
as_app() { sudo -u "$APP_USER" -H env PATH="$RUBY_DIR/bin:/usr/local/bin:/usr/bin:/bin" HOME="/home/$APP_USER" bash -c "$*"; }

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
  build-essential git curl pkg-config autoconf bison patch \
  libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libgmp-dev libgdbm-dev libdb-dev uuid-dev \
  libpq-dev postgresql postgresql-contrib nginx certbot python3-certbot-nginx ufw unattended-upgrades

echo "== swap (or-tools' C++ extension needs several GB to compile)"
SWAP_GB=4
current_kb=$(awk '/^\/swapfile/ {print $3}' /proc/swaps 2>/dev/null || true)
if [ -z "$current_kb" ] || [ "$current_kb" -lt $((SWAP_GB * 1000 * 1000)) ]; then
  swapoff /swapfile 2>/dev/null || true; rm -f /swapfile
  fallocate -l ${SWAP_GB}G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "   ${SWAP_GB}G swapfile active"
fi

echo "== Ruby $RUBY_VERSION at $RUBY_DIR (system-wide; ~15-25 minutes on one core if not already built)"
if [ ! -x "$RUBY_DIR/bin/ruby" ]; then
  [ -d /opt/ruby-build ] || git clone -q https://github.com/rbenv/ruby-build.git /opt/ruby-build
  git -C /opt/ruby-build pull -q
  RUBY_CONFIGURE_OPTS=--disable-install-doc /opt/ruby-build/bin/ruby-build "$RUBY_VERSION" "$RUBY_DIR"
fi
"$RUBY_DIR/bin/ruby" -v
"$RUBY_DIR/bin/gem" list -i bundler -v "$BUNDLER_VERSION" >/dev/null || "$RUBY_DIR/bin/gem" install bundler -v "$BUNDLER_VERSION" --no-document
ln -sf "$BUNDLE" /usr/local/bin/bundle   # so the runbook's plain `bundle exec …` works

echo "== $ENV_FILE"
mkdir -p /etc/abid
if [ ! -f "$ENV_FILE" ]; then
  sed -e "s/CHANGE_ME_long_random/$(openssl rand -hex 24)/" \
      -e "s/CHANGE_ME_128_hex_chars/$(openssl rand -hex 64)/" \
      "$APP_DIR/deploy/env.example" > "$ENV_FILE"
  echo "   wrote new secrets"
fi
if grep -q '^ABID_ROOT_PATH=' "$ENV_FILE"; then
  sed -i "s|^ABID_ROOT_PATH=.*|ABID_ROOT_PATH=$PREFIX|" "$ENV_FILE"
else
  printf '\n# Mounted under this prefix; nginx routes it. Empty = domain root.\nABID_ROOT_PATH=%s\n' "$PREFIX" >> "$ENV_FILE"
fi
chown root:"$APP_USER" "$ENV_FILE"; chmod 640 "$ENV_FILE"
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

echo "== postgres role + database"
systemctl enable --now postgresql
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD';
  ELSE
    ALTER ROLE $DB_USER WITH PASSWORD '$DB_PASSWORD';
  END IF;
END \$\$;
SQL
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
  || sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

echo "== gems (as $APP_USER, into vendor/bundle)"
rm -rf "$APP_DIR/vendor/bundle/ruby/3.2.0"
as_app "cd $APP_DIR && bundle config set --local path vendor/bundle && bundle config set --local without 'development test' && MAKEFLAGS=-j1 bundle install --quiet"
as_app "cd $APP_DIR && bundle exec ruby -e 'require \"or-tools\"; puts \"   or-tools \" + Gem.loaded_specs[\"or-tools\"].version.to_s + \" loads\"'"
as_app "cd $APP_DIR && RACK_ENV=production DB_USER=$DB_USER DB_PASSWORD=$DB_PASSWORD DB_NAME=$DB_NAME DB_HOST=$DB_HOST bundle exec rake db:migrate 2>&1 | grep -vE '^D, |warning:' | tail -2"

echo "== systemd units (enabled)"
install -m 644 "$APP_DIR/deploy/abid-web.service" "$APP_DIR/deploy/abid-bot.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable abid-web abid-bot >/dev/null

echo "== let $OPERATOR operate the two services without a password"
cat > /etc/sudoers.d/abid <<EOF2
$OPERATOR ALL=(root) NOPASSWD: /usr/bin/systemctl start abid-web, /usr/bin/systemctl stop abid-web, /usr/bin/systemctl restart abid-web, /usr/bin/systemctl status abid-web, /usr/bin/systemctl status abid-web *, \\
                              /usr/bin/systemctl start abid-bot, /usr/bin/systemctl stop abid-bot, /usr/bin/systemctl restart abid-bot, /usr/bin/systemctl status abid-bot, /usr/bin/systemctl status abid-bot *, \\
                              /usr/bin/journalctl -u abid-web *, /usr/bin/journalctl -u abid-bot *, \\
                              /usr/bin/nginx -t, /usr/bin/systemctl reload nginx, /usr/bin/certbot *
EOF2
chmod 440 /etc/sudoers.d/abid; visudo -cf /etc/sudoers.d/abid >/dev/null

echo "== hardening: firewall, automatic security updates, key-only SSH"
ufw allow OpenSSH >/dev/null; ufw allow 'Nginx Full' >/dev/null; ufw --force enable >/dev/null
dpkg-reconfigure -f noninteractive unattended-upgrades
if [ -s "/home/$OPERATOR/.ssh/authorized_keys" ]; then
  mkdir -p /etc/ssh/sshd_config.d
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/90-abid.conf
  sshd -t && systemctl reload ssh
else
  echo "   WARNING: no authorized_keys for $OPERATOR — leaving SSH password login ON"
fi

echo "== nginx: $PREFIX/ -> puma (TLS lines from certbot are never touched)"
if [ ! -f "$SITE" ]; then
  install -m 644 "$APP_DIR/deploy/nginx-abid.conf" "$SITE"
  [ -n "$HOSTNAME_ARG" ] && sed -i "s/RIDES_HOSTNAME/$HOSTNAME_ARG www.$HOSTNAME_ARG/" "$SITE"
fi
python3 - "$SITE" "$PREFIX" <<'PY'
import re, sys
site, prefix = sys.argv[1], sys.argv[2]
s = open(site).read()
# Any old prefix block (or the root block) becomes the app block for this prefix.
s = re.sub(r"location = / \{ return 302 [^}]*\}\n", "", s)
s = re.sub(r"location = /\w+ \{ return 301 [^}]*\}\n\n?", "", s)
s = re.sub(r"location (/\w+/|/) \{\n(\s+proxy_pass http://127\.0\.0\.1:5544;)", f"location {prefix}/ {{\n\\2", s, count=1)
s = re.sub(r"location ~\* [^\n]*\.\(css\|js\|webp\|png\|ico\)\$ \{", f"location ~* ^{prefix}/.*\\.(css|js|webp|png|ico)$ {{", s)
if f"return 302 {prefix}/" not in s:
    s = s.replace(f"    location {prefix}/ {{",
                  f"    location = / {{ return 302 {prefix}/; }}\n    location = {prefix} {{ return 301 {prefix}/; }}\n\n    location {prefix}/ {{", 1)
open(site, "w").write(s)
PY
rm -f /etc/nginx/sites-enabled/default; ln -sf "$SITE" /etc/nginx/sites-enabled/abid; mkdir -p /var/www/html
nginx -t -q && systemctl enable --now nginx >/dev/null && systemctl reload nginx

if [ -n "$HOSTNAME_ARG" ] && [ ! -d "/etc/letsencrypt/live/$HOSTNAME_ARG" ]; then
  echo "== HTTPS for $HOSTNAME_ARG (Let's Encrypt)"
  certbot --nginx -d "$HOSTNAME_ARG" -d "www.$HOSTNAME_ARG" --non-interactive --agree-tos --redirect \
    ${CERTBOT_EMAIL:+-m "$CERTBOT_EMAIL"} ${CERTBOT_EMAIL:---register-unsafely-without-email} \
    || echo "   WARNING: certbot failed — is DNS pointing here yet? Re-run: sudo certbot --nginx -d $HOSTNAME_ARG -d www.$HOSTNAME_ARG"
fi

echo "== start"
systemctl restart abid-web
systemctl restart abid-bot
sleep 8
for u in abid-web abid-bot; do printf "   %-9s %s\n" "$u" "$(systemctl is-active $u)"; done
echo "   local:  HTTP $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5544$PREFIX/login)"
[ -n "$HOSTNAME_ARG" ] && echo "   public: https://$HOSTNAME_ARG$PREFIX/  ->  HTTP $(curl -s -o /dev/null -w '%{http_code}' https://$HOSTNAME_ARG$PREFIX/login)"
echo "done."
