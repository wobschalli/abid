# Deploying Abid

Plain systemd + nginx + Let's Encrypt on Ubuntu 24.04. The checkout lives at
`/opt/abid`, owned by the `abid` service account; Ruby 3.3.8 comes from the
system-wide rbenv at `/usr/local/rbenv`; puma listens on a unix socket; the
dashboard is served under `/abidebot/`. The Dockerfile in the
repo root predates the bot and the optimizer and does not run this app; use
this instead.

Two rules that matter more than anything below:

1. **The bot runs in exactly one place.** A second instance posts every
   sign-up twice into a channel of eighty people. Stop the old one, confirm it
   is dead, then start the new one.
2. **The dashboard is never on plain HTTP.** It holds members' phone numbers
   and home addresses. Puma binds to `127.0.0.1:5544` only; until the TLS
   certificate exists, reach it over an SSH tunnel.

## 1. One-time server setup (needs sudo, once)

    cd /opt/abid && git pull && sudo bash deploy/install.sh rides.example.org

Installs Ruby 3.3.8 via rbenv (Ubuntu's packaged 3.2 makes bundler silently
resolve an older or-tools than the one the optimizer is tested on), Postgres,
nginx, certbot; writes `/etc/abid/env` with generated secrets; creates the
`abid` database role; `bundle install`s (or-tools compiles a C++ extension:
slow, and it needs the 4 GB swapfile the script creates); installs and
enables (but does not start) `abid-web` and `abid-bot`; grants your user
passwordless `systemctl start/stop/restart/status` for those two units only;
firewalls the box to 22/80/443 and turns on unattended security updates.
Given a hostname whose DNS already points at the server, it also configures
nginx and obtains the Let's Encrypt certificate (step 4 is then done).
`CERTBOT_EMAIL=you@example.org sudo -E bash deploy/install.sh …` to get
certificate-expiry notices; renewal itself is automatic regardless.

## 2. Move the data and the secrets (no sudo)

From the laptop:

    pg_dump -Fc -h localhost -U postgres abid_development > /tmp/abid.dump
    scp /tmp/abid.dump config.yml alan@SERVER:/opt/abid/tmp/

On the server:

    cd /opt/abid && set -a && . /etc/abid/env && set +a
    pg_restore -h localhost -U "$DB_USER" -d "$DB_NAME" --no-owner --no-privileges --clean --if-exists tmp/abid.dump
    mv tmp/config.yml ./config.yml && chmod 600 config.yml && rm tmp/abid.dump
    bundle exec rake db:migrate      # no-op if the dump is current

`config.yml` carries the Discord token and the Google key; it is gitignored
and must be `chmod 600`. **Reset the Discord bot token first** if it has ever
been pasted anywhere (Developer Portal → Bot → Reset Token) and put the new one
in this file before the bot starts.

## 3. Cut over

    # laptop: stop its bot and confirm nothing is left
    pkill -f 'ruby bot/run.rb'; pgrep -f 'ruby bot/run.rb' || echo "laptop bot stopped"

    # server
    sudo systemctl start abid-web && sudo systemctl status abid-web --no-pager
    sudo systemctl start abid-bot && sudo journalctl -u abid-bot -n 20 --no-pager

The bot log should show one `gateway protocol` line. The web is reachable
straight away over a tunnel: `ssh -L 5544:localhost:5544 alan@SERVER`, then
http://localhost:5544.

## 4. HTTPS (only if the installer ran without a hostname)

    sudo sed -i 's/RIDES_HOSTNAME/rides.example.org/' /etc/nginx/sites-available/abid
    sudo nginx -t && sudo systemctl reload nginx
    sudo certbot --nginx -d rides.example.org

Certbot adds the 443 block and the 80 → 443 redirect, and installs its own
renewal timer.

## The /abidebot/ prefix

The dashboard is served at `https://abidepurdue.com/abidebot/` so the domain
root stays free. Two settings make that work, both applied by

    sudo bash deploy/install.sh abidepurdue.com   # idempotent; also applies the prefix

which patches the certbot-managed nginx site (`location /abidebot/` proxied
with the prefix intact, `/` redirecting there for now) and sets
`ABID_ROOT_PATH=/abidebot` in `/etc/abid/env`. The app mounts itself at that
path (`config.ru`), so every link, form, redirect and asset it emits carries
it; nothing is rewritten by nginx. Leave `ABID_ROOT_PATH` empty to serve at
the root again.

## Day to day

    sudo -u abid env HOME=/tmp git -C /opt/abid pull && sudo systemctl restart abid-web abid-bot
    sudo journalctl -u abid-bot -f                  # watch the bot
    cd /opt/abid && bundle exec rake db:migrate        # when a pull adds a migration

Both units `Restart=always`, so a crash or a reboot brings them back. The
publisher retries transient network errors for ~10 minutes and then marks a
post failed for a human; the dashboard's sign-up page says why.

## Background jobs (que) — off by default

Optimize can run as a background job instead of inside the web request
(`jobs/optimize_job.rb`). It is **off unless `ABID_JOBS=1`** is in
`/etc/abid/env`, so deploying this code changes nothing by itself.

To turn it on (after a `git pull`):

    cd /opt/abid && sudo -u abid env HOME=/tmp bundle install      # adds the que gem
    sudo -u abid env HOME=/tmp RACK_ENV=production bundle exec rake db:migrate   # que's table
    echo 'ABID_JOBS=1' | sudo tee -a /etc/abid/env
    sudo systemctl restart abid-web abid-bot

The worker runs as threads inside `abid-bot` (no Redis, no extra process).
If it fails to start, the bot logs it and carries on; queued jobs wait.
To turn it off: remove the `ABID_JOBS=1` line and restart both services.
Sign-up posting does not go through que.
