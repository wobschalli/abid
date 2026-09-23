#!/usr/bin/env bash
# One-shot server setup for Ubuntu 24.04. Run ONCE as root from the repo:
#
#   sudo bash deploy/install.sh rides.example.org
#
# With a hostname, it also configures nginx for it and obtains the Let's
# Encrypt certificate (DNS must already point here). Set CERTBOT_EMAIL=you@x
# in the environment to receive expiry notices; without it the certificate is
# registered without an address — renewal is automatic either way.
#
# Idempotent: safe to re-run after a git pull, and re-running is how a failed
# step is finished. It installs system packages, Ruby 3.3.8 via rbenv (the
# version the app is tested on — Ubuntu's 3.2 makes bundler silently pick an
# older or-tools), Postgres, nginx and certbot; writes /etc/abid/env with
# generated secrets (never overwriting an existing one); creates the database
# role; installs the gems; and installs the two systemd units — ENABLED BUT
# NOT STARTED. Starting is a separate, deliberate step (deploy/DEPLOY.md):
# the bot in particular must never run in two places at once.
#
# On a 1-core, 2GB box expect 30-45 minutes: Ruby compiles, and or-tools'
# Rice extension is memory-hungry enough that it needs the swapfile below.
set -euo pipefail

APP_USER=alan
HOSTNAME_ARG=${1:-}
APP_DIR=${APP_DIR:-/opt/abid}
ENV_FILE=/etc/abid/env
RUBY_VERSION=3.3.8
BUNDLER_VERSION=2.6.9
RBENV_ROOT=/home/$APP_USER/.rbenv
BUNDLE=$RBENV_ROOT/shims/bundle

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$APP_DIR/Gemfile" ] || { echo "no app at $APP_DIR"; exit 1; }
# The services run as $APP_USER and git pull / bundle / tmp writes happen as
# them, so the checkout has to be theirs — a root-owned clone under /opt is
# the common way for the first `git pull` to fail.
[ "$(stat -c %U "$APP_DIR")" = "$APP_USER" ] || chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

as_app() { sudo -u "$APP_USER" -H env PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:/usr/local/bin:/usr/bin:/bin" bash -c "$*"; }

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends \
  build-essential git curl pkg-config autoconf bison patch \
  libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libgmp-dev libgdbm-dev libdb-dev uuid-dev \
  libpq-dev postgresql postgresql-contrib nginx certbot python3-certbot-nginx

echo "== swap (or-tools' Rice extension needs several GB to compile; the OOM killer took cc1plus with 1GB)"
SWAP_GB=4
current_kb=$(awk '/^\/swapfile/ {print $3}' /proc/swaps 2>/dev/null || true)
if [ -z "$current_kb" ] || [ "$current_kb" -lt $((SWAP_GB * 1000 * 1000)) ]; then
  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  fallocate -l ${SWAP_GB}G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "   ${SWAP_GB}G swapfile active"
fi

echo "== Ruby $RUBY_VERSION via rbenv (as $APP_USER; ~15-25 minutes on one core if not already built)"
[ -d "$RBENV_ROOT" ] || as_app "git clone -q https://github.com/rbenv/rbenv.git $RBENV_ROOT"
[ -d "$RBENV_ROOT/plugins/ruby-build" ] || as_app "git clone -q https://github.com/rbenv/ruby-build.git $RBENV_ROOT/plugins/ruby-build"
as_app "cd $RBENV_ROOT/plugins/ruby-build && git pull -q"
as_app "RUBY_CONFIGURE_OPTS=--disable-install-doc rbenv install -s $RUBY_VERSION"
as_app "rbenv global $RUBY_VERSION && rbenv rehash"
as_app "ruby -v"
as_app "gem list -i bundler -v $BUNDLER_VERSION >/dev/null || gem install bundler -v $BUNDLER_VERSION --no-document; rbenv rehash"
# So the runbook's plain `bundle exec …` works in any shell.
ln -sf "$BUNDLE" /usr/local/bin/bundle

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

echo "== gems (as $APP_USER, into vendor/bundle; or-tools compiles a C++ extension — slow, single job)"
# Leftovers from an attempt under Ubuntu's Ruby 3.2 (which resolved the wrong or-tools).
rm -rf "$APP_DIR/vendor/bundle/ruby/3.2.0"
as_app "cd $APP_DIR && bundle config set --local path vendor/bundle && bundle config set --local without 'development test' && MAKEFLAGS=-j1 bundle install --quiet"
as_app "cd $APP_DIR && bundle exec ruby -e 'require \"or-tools\"; puts \"   or-tools \" + Gem.loaded_specs[\"or-tools\"].version.to_s + \" loads\"'"

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

echo "== hardening: firewall, automatic security updates, key-only SSH"
# The realistic threats to a box holding 80 people's phone numbers are a
# guessed password, an exposed port, and an unpatched package — not a DDoS.
apt-get install -y -q --no-install-recommends ufw unattended-upgrades
ufw allow OpenSSH >/dev/null          # before enabling, or this session is the last
ufw allow 'Nginx Full' >/dev/null     # 80 for the ACME challenge, 443 for the app
ufw --force enable >/dev/null
dpkg-reconfigure -f noninteractive unattended-upgrades
if [ -s "/home/$APP_USER/.ssh/authorized_keys" ]; then
  # Keys are in place, so password logins are only a liability.
  mkdir -p /etc/ssh/sshd_config.d
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/90-abid.conf
  sshd -t && systemctl reload ssh
  echo "   SSH password logins disabled (keys present for $APP_USER)"
else
  echo "   WARNING: no authorized_keys for $APP_USER — leaving SSH password login ON. Add a key, then disable it."
fi

echo "== nginx site (puma is localhost-only regardless)"
if grep -q "managed by Certbot" /etc/nginx/sites-available/abid 2>/dev/null; then
  echo "   site already exists and carries certbot's TLS config — left untouched (edit it directly, or deploy/apply-ridebot-prefix.sh)"
  SITE_MANAGED=1
else
  install -m 644 "$APP_DIR/deploy/nginx-abid.conf" /etc/nginx/sites-available/abid
fi
# Cover www. too when it already points at this machine — one certificate,
# both names. Skipped silently otherwise, so a missing CNAME never fails the
# apex certificate.
NAMES=("$HOSTNAME_ARG")
if [ -n "$HOSTNAME_ARG" ] && [ -z "${SITE_MANAGED:-}" ]; then
  MY_IP=$(curl -s -m 5 https://ifconfig.me || true)
  WWW_IP=$(getent ahostsv4 "www.$HOSTNAME_ARG" 2>/dev/null | awk 'NR==1{print $1}')
  if [ -n "$MY_IP" ] && [ "$WWW_IP" = "$MY_IP" ]; then
    NAMES+=("www.$HOSTNAME_ARG")
    echo "   www.$HOSTNAME_ARG points here too — including it"
  fi
  sed -i "s/server_name RIDES_HOSTNAME;/server_name ${NAMES[*]};/" /etc/nginx/sites-available/abid
fi
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/abid /etc/nginx/sites-enabled/abid
mkdir -p /var/www/html
nginx -t -q && systemctl enable --now nginx && systemctl reload nginx

if [ -n "$HOSTNAME_ARG" ] && [ -d "/etc/letsencrypt/live/$HOSTNAME_ARG" ]; then
  echo "== HTTPS: certificate for $HOSTNAME_ARG already present (renewal is automatic)"
elif [ -n "$HOSTNAME_ARG" ]; then
  echo "== HTTPS for ${NAMES[*]} (Let's Encrypt)"
  if [ -n "${CERTBOT_EMAIL:-}" ]; then
    EMAIL_OPTS=(-m "$CERTBOT_EMAIL")
  else
    EMAIL_OPTS=(--register-unsafely-without-email)
  fi
  DOMAIN_OPTS=(); for n in "${NAMES[@]}"; do DOMAIN_OPTS+=(-d "$n"); done
  # The dashboard holds members' phone numbers: --redirect makes plain HTTP
  # a redirect to HTTPS, never a page.
  if certbot --nginx "${DOMAIN_OPTS[@]}" --non-interactive --agree-tos --redirect "${EMAIL_OPTS[@]}"; then
    echo "   certificate installed; renewal timer: $(systemctl is-enabled certbot.timer 2>/dev/null || echo 'check systemctl list-timers')"
  else
    echo "   WARNING: certbot failed — is DNS for $HOSTNAME_ARG pointing at this server yet? Re-run: sudo certbot --nginx ${DOMAIN_OPTS[*]}"
  fi
else
  echo "== no hostname given: nginx serves HTTP only on the IP; use an SSH tunnel until certbot runs"
fi

echo
echo "done. Next: restore the database and config.yml, then start the services — deploy/DEPLOY.md"
