# Deploying abid

Pushing to `main` builds a Docker image, pushes it to GitHub Container Registry,
and restarts the stack on your server over SSH. The stack is three containers:

| Service | What it runs | Notes |
| --- | --- | --- |
| `db` | `postgres:16` | Data lives in the `db_data` volume |
| `web` | Puma serving `config.ru` (the Sinatra interface) | Runs migrations on boot |
| `bot` | `bin/bot` (the Discord bot) | Starts after `web`, so they never race on migrations |

Both app containers come from the same image, so the bot and the web interface
can never drift out of sync.

## One-time server setup

1. Install Docker and the Compose plugin on the server.

2. Create the deploy directory and a user that can run `docker`:

   ```sh
   sudo mkdir -p /srv/abid
   sudo chown "$USER" /srv/abid
   ```

3. Create `/srv/abid/.env` from [`.env.production.example`](.env.production.example)
   and fill in real values:

   ```sh
   # generate a session secret
   ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
   ```

   Keep `DISCORD_TOKEN` empty here — production reads the bot token from the
   seeded `discord_infos` row.

4. Copy `config.yml` (the gitignored secrets file) to the server, then seed the
   database once the first deploy has created it:

   ```sh
   cd /srv/abid
   docker compose -f docker-compose.prod.yml run --rm \
     -v ./config.yml:/abid/config.yml:ro \
     web bundle exec rake db:seed
   ```

5. Put nginx or Caddy in front of `WEB_PORT` for TLS. The app has no HTTPS of
   its own, and sessions are cookie-based, so don't expose it directly.

## One-time GitHub setup

Add these under **Settings → Secrets and variables → Actions**. If you use the
`production` environment (the workflow references it), add them there.

| Secret | Example | Purpose |
| --- | --- | --- |
| `SSH_HOST` | `abid.example.com` | Server hostname or IP |
| `SSH_USER` | `deploy` | User that can run `docker` |
| `SSH_KEY` | *(private key, full PEM body)* | Passphrase-less key whose public half is in the server's `authorized_keys` |
| `SSH_PORT` | `22` | Optional, defaults to `22` |
| `DEPLOY_PATH` | `/srv/abid` | Directory holding `.env` |

No registry credentials are needed: the workflow logs in to ghcr.io with the
automatic `GITHUB_TOKEN`, and the server reuses that token for the duration of
the job only.

## Deploying

Push to `main`, or run the **Deploy** workflow manually from the Actions tab.
Each run:

1. builds `ghcr.io/wobschalli/abid` and tags it `latest` and `<commit sha>`,
2. copies `docker-compose.prod.yml` to `$DEPLOY_PATH`,
3. pins `APP_IMAGE` in the server's `.env` to that exact sha,
4. runs `docker compose pull && docker compose up -d`.

Because the release is pinned by sha, rolling back is just:

```sh
cd /srv/abid
sed -i 's|^APP_IMAGE=.*|APP_IMAGE=ghcr.io/wobschalli/abid:<old-sha>|' .env
docker compose -f docker-compose.prod.yml up -d
```

## Operating

```sh
cd /srv/abid
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f bot
docker compose -f docker-compose.prod.yml restart bot

# database backup
docker compose -f docker-compose.prod.yml exec db \
  pg_dump -U postgres abid_production > backup-$(date +%F).sql
```

## Running a beta bot locally

So you can develop against a throwaway Discord application instead of the live
one, the bot reads `DISCORD_TOKEN` from the environment and — when it is set —
uses that instead of the token seeded into the database.

1. Copy [`.env.local.example`](.env.local.example) to `.env.local` (gitignored)
   and put your beta application's token in `DISCORD_TOKEN`.

2. `bin/bot` and `bin/dev` source `.env.local` automatically:

   ```sh
   docker compose up -d   # local Postgres
   bin/bot                # bot on the beta token
   bin/dev                # web interface on http://localhost:4455
   ```

3. Your beta bot is in different servers, so seed your dev database from the
   matching config file:

   ```sh
   CONFIG_FILE=config2.yml bundle exec rake db:seed
   ```

   `CONFIG_FILE` defaults to `config.yml`.

Leave `DISCORD_TOKEN` unset (or empty) to fall back to the seeded token — that
is what production does.

## Configuration reference

Every setting is an environment variable, so the same image runs locally and in
production.

| Variable | Default | Used by |
| --- | --- | --- |
| `RACK_ENV` | `development` | Web: which `config/database.yml` section to use |
| `BOT_ENV` | `development` | Bot: which `config/database.yml` section to use |
| `DB_HOST` / `DB_PORT` | `localhost` / `5432` | Both |
| `DB_USER` / `DB_PASSWORD` | `postgres` / `password` | Both |
| `DB_NAME` | per-environment default | Both |
| `SESSION_SECRET` | falls back to the `.session_secret` file | Web |
| `DISCORD_TOKEN` | falls back to the `discord_infos` row | Bot |
| `CONFIG_FILE` | `config.yml` | `rake db:seed` |
| `RUN_MIGRATIONS` | unset | Container entrypoint; `true` migrates on boot |
| `APP_IMAGE` / `WEB_PORT` | — | `docker-compose.prod.yml` |
