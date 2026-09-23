#!/usr/bin/env bash
# One-shot server setup for Ubuntu 24.04. Run ONCE as root from the repo:
#
#   sudo bash deploy/install.sh
#
# Idempotent: safe to re-run after a git pull. It installs system packages,
# Postgres, nginx and certbot, writes /etc/abid/env with generated secrets
# (never overwriting an existing one), creates the database role, installs
# the gems, and installs the two systemd units — ENABLED BUT NOT STARTED.
# Starting is a separate, deliberate step (see deploy/DEPLOY.md): the bot in
# particular must never run in two places at once.
set -euo pipefail

APP_USER=alan
APP_DIR=/home/$APP_USER/abid
ENV_FILE=/etc/abid/env
BUNDLER_VERSION=2.6.9

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$APP_DIR/Gemfile" ] || { echo "no app at $APP_DIR"; exit 1; }

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
  ruby ruby-dev build-essential libpq-dev libyaml-dev libffi-dev zlib1g-dev pkg-config git curl \
  postgresql postgresql-contrib nginx certbot python3-certbot-nginx

echo "== swap (a 1.9GB box needs headroom for bundle install)"
if ! swapon --show | grep -q .; then
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "== bundler $BUNDLER_VERSION (matches Gemfile.lock)"
gem list -i bundler -v "$BUNDLER_VERSION" >/dev/null || gem install bundler -v "$BUNDLER_VERSION" --no-document
ln -sf "$(gem contents bundler -v "$BUNDLER_VERSION" | grep -m1 'exe/bundle$')" /usr/local/bin/bundle

echo "== $ENV_FILE"
mkdir -p /etc/abid
if [ ! -f "$ENV_FILE" ]; then
  DB_PASSWORD=$(openssl rand -hex 24)
  SESSION_SECRET=$(openssl rand -hex 64)
  sed -e "s/CHANGE_ME_long_random/$DB_PASSWORD/" \
      -e "s/CHANGE_ME_128_hex_chars/$SESSION_SECRET/" \
      "$APP_DIR/deploy/env.example" > "$ENV_FILE"
  echo "   wrote new secrets"
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
sudo -u "$APP_USER" -H bash -c "cd $APP_DIR && bundle config set --local path vendor/bundle && bundle config set --local without 'development test' && bundle install --quiet"

echo "== systemd units (enabled, NOT started)"
install -m 644 "$APP_DIR/deploy/abid-web.service" "$APP_DIR/deploy/abid-bot.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable abid-web abid-bot >/dev/null

echo "== let $APP_USER operate the two services without a password"
cat > /etc/sudoers.d/abid <<EOF
$APP_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start abid-web, /usr/bin/systemctl stop abid-web, /usr/bin/systemctl restart abid-web, /usr/bin/systemctl status abid-web, \\
                              /usr/bin/systemctl start abid-bot, /usr/bin/systemctl stop abid-bot, /usr/bin/systemctl restart abid-bot, /usr/bin/systemctl status abid-bot, \\
                              /usr/bin/journalctl -u abid-web *, /usr/bin/journalctl -u abid-bot *, \\
                              /usr/bin/nginx -t, /usr/bin/systemctl reload nginx, /usr/bin/certbot *
EOF
chmod 440 /etc/sudoers.d/abid; visudo -cf /etc/sudoers.d/abid >/dev/null

echo "== nginx site (HTTP only until certbot runs; puma is localhost-only regardless)"
install -m 644 "$APP_DIR/deploy/nginx-abid.conf" /etc/nginx/sites-available/abid
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/abid /etc/nginx/sites-enabled/abid
nginx -t -q && systemctl enable --now nginx && systemctl reload nginx

echo
echo "done. Next: restore the database and config.yml, then start the services — deploy/DEPLOY.md"
