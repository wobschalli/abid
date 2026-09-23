#!/usr/bin/env bash
# Reconcile the server with the deployed layout. Run as root from the repo:
#
#   sudo bash deploy/install.sh abidepurdue.com
#
# Adopts what is already on the box rather than installing alongside it:
#   /usr/local/rbenv     Ruby 3.3.8, system-wide (must already exist)
#   /opt/abid            the checkout, owned by the `abid` service account
#   /etc/abid/env        secrets and settings, root:abid 640
#   abid-web, abid-bot   systemd units running as `abid`; puma on a unix socket
#   nginx                TLS via certbot; the app served under /abidebot/
# The human operator (OPERATOR, default alan) gets passwordless systemctl and
# journalctl for the two units, and nothing else. Idempotent; takes seconds.
set -euo pipefail

APP_USER=${APP_USER:-abid}
OPERATOR=${OPERATOR:-alan}
APP_DIR=${APP_DIR:-/opt/abid}
PREFIX=${PREFIX:-/abidebot}
HOSTNAME_ARG=${1:-}
ENV_FILE=/etc/abid/env
RBENV_ROOT=/usr/local/rbenv
RUBY_VERSION=3.3.8
SITE=/etc/nginx/sites-available/abid

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$APP_DIR/Gemfile" ] || { echo "no app at $APP_DIR"; exit 1; }
[ -x "$RBENV_ROOT/versions/$RUBY_VERSION/bin/ruby" ] || { echo "expected Ruby $RUBY_VERSION at $RBENV_ROOT/versions — install it there first (rbenv install $RUBY_VERSION)"; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "no user $APP_USER — create the service account first"; exit 1; }

echo "== leftovers from an earlier installer: a second Ruby under /opt (the one under $RBENV_ROOT is the real one)"
rm -rf /opt/ruby /opt/ruby-build
[ -L /usr/local/bin/bundle ] && [ ! -e /usr/local/bin/bundle ] && rm -f /usr/local/bin/bundle
ln -sfn "$RBENV_ROOT/shims/bundle" /usr/local/bin/bundle

echo "== checkout: owned by $APP_USER, modes ignored by git, config.yml private"
mkdir -p "/home/$APP_USER"; chown "$APP_USER":"$APP_USER" "/home/$APP_USER"
if find "$APP_DIR" ! -user "$APP_USER" -print -quit | grep -q .; then
  chown -R "$APP_USER":"$APP_USER" "$APP_DIR"; echo "   chowned to $APP_USER"
fi
# A recursive chmod made every tracked file look modified; mode bits carry no
# meaning here, so tell git to ignore them rather than fight about it.
sudo -u "$APP_USER" git -C "$APP_DIR" config core.fileMode false
[ -f "$APP_DIR/config.yml" ] && chmod 600 "$APP_DIR/config.yml"
mkdir -p "$APP_DIR/tmp/sockets"; chown -R "$APP_USER":"$APP_USER" "$APP_DIR/tmp"
as_app() { sudo -u "$APP_USER" -H env RBENV_ROOT="$RBENV_ROOT" PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/local/bin:/usr/bin:/bin" HOME="/home/$APP_USER" bash -c "$*"; }

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
systemctl enable --now postgresql >/dev/null 2>&1 || true
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

echo "== gems + migrations (as $APP_USER)"
as_app "cd $APP_DIR && bundle config set --local path vendor/bundle >/dev/null && bundle config set --local without 'development test' >/dev/null && MAKEFLAGS=-j1 bundle install --quiet"
as_app "cd $APP_DIR && bundle exec ruby -e 'require \"or-tools\"; puts \"   or-tools \" + Gem.loaded_specs[\"or-tools\"].version.to_s + \" loads\"'"
as_app "cd $APP_DIR && RACK_ENV=production DB_USER='$DB_USER' DB_PASSWORD='$DB_PASSWORD' DB_NAME='$DB_NAME' DB_HOST='${DB_HOST:-localhost}' bundle exec rake db:migrate 2>&1 | grep -vE '^D, |warning:' | tail -2"

echo "== systemd units"
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

echo "== nginx: $PREFIX/ -> puma socket (certbot's TLS lines are never touched)"
if [ ! -f "$SITE" ]; then
  install -m 644 "$APP_DIR/deploy/nginx-abid.conf" "$SITE"
  [ -n "$HOSTNAME_ARG" ] && sed -i "s/RIDES_HOSTNAME/$HOSTNAME_ARG www.$HOSTNAME_ARG/" "$SITE"
fi
python3 - "$SITE" "$PREFIX" <<'PY'
import re, sys
site, prefix = sys.argv[1], sys.argv[2]
s = open(site).read()
if "upstream puma_abid" not in s:
    s = "upstream puma_abid {\n    server unix:/opt/abid/tmp/sockets/abid-web.sock fail_timeout=0;\n}\n\n" + s
s = re.sub(r"[ \t]*location = / \{ return 302 [^}]*\}\n", "", s)
s = re.sub(r"[ \t]*location = /\w+ \{ return 301 [^}]*\}\n\n?", "", s)
# whichever app block exists (root, or an older prefix) becomes this prefix's, pointed at the socket
s = re.sub(r"location (?:/\w+/|/) \{\n(\s+)proxy_pass http://[^;]+;", f"location {prefix}/ {{\n\\1proxy_pass http://puma_abid;", s, count=1)
s = re.sub(r"location ~\* [^\n]*\\\.\(css\|js\|webp\|png\|ico\)\$ \{\n(\s+)proxy_pass http://[^;]+;",
           f"location ~* ^{prefix}/.*\\\\.(css|js|webp|png|ico)$ {{\n\\1proxy_pass http://puma_abid;", s)
if f"return 302 {prefix}/" not in s:
    s = s.replace(f"    location {prefix}/ {{",
                  f"    location = / {{ return 302 {prefix}/; }}\n    location = {prefix} {{ return 301 {prefix}/; }}\n\n    location {prefix}/ {{", 1)
open(site, "w").write(s)
PY
rm -f /etc/nginx/sites-enabled/default; ln -sfn "$SITE" /etc/nginx/sites-enabled/abid; mkdir -p /var/www/html
nginx -t -q && systemctl enable --now nginx >/dev/null 2>&1; systemctl reload nginx

if [ -n "$HOSTNAME_ARG" ] && [ ! -d "/etc/letsencrypt/live/$HOSTNAME_ARG" ]; then
  echo "== HTTPS for $HOSTNAME_ARG (Let's Encrypt)"
  certbot --nginx -d "$HOSTNAME_ARG" -d "www.$HOSTNAME_ARG" --non-interactive --agree-tos --redirect \
    ${CERTBOT_EMAIL:+-m "$CERTBOT_EMAIL"} ${CERTBOT_EMAIL:---register-unsafely-without-email} \
    || echo "   WARNING: certbot failed — re-run: sudo certbot --nginx -d $HOSTNAME_ARG -d www.$HOSTNAME_ARG"
fi

echo "== start"
systemctl restart abid-web
systemctl restart abid-bot
sleep 8
for u in abid-web abid-bot; do printf "   %-9s %s\n" "$u" "$(systemctl is-active $u)"; done
echo "   socket: $([ -S $APP_DIR/tmp/sockets/abid-web.sock ] && echo present || echo MISSING)"
[ -n "$HOSTNAME_ARG" ] && echo "   public: https://$HOSTNAME_ARG$PREFIX/login  ->  HTTP $(curl -s -o /dev/null -w '%{http_code}' https://$HOSTNAME_ARG$PREFIX/login)"
echo "   bot: $(journalctl -u abid-bot --since '-30 sec' --no-pager -o cat | grep -ciE 'gateway protocol') gateway connection(s)"
echo "done."
