# abid
All the code for the Abide CF Discord bot

## Installation
Ensure you have ruby, bundler, npm, yarn, docker, and docker-compose, then run `yarn install` and `bundle install`. Afterwards run `rake -T` to initialize rake tasks

## Configuration
Secrets come from the environment, falling back to the old file/DB sources so
existing installs keep working:

| Variable | Falls back to | Used for |
| --- | --- | --- |
| `DISCORD_TOKEN` | `discord_infos.token` | bot login |
| `ABID_SESSION_SECRET` | `.session_secret` | web session cookies |
| `DB_PASSWORD` / `DB_USER` / `DB_HOST` / `DB_NAME` | dev defaults | Postgres |
| `ABID_TZ` | `America/Indiana/Indianapolis` | both halves |

Production has no default database password on purpose.

`db/seeds.rb` still reads a gitignored `config.yml` for the initial Discord
server/channel/emoji ids.

## Running
Start the database with `docker-compose`, then run the bot with `bin/bot`\
Web interface will be run seperately by running `bin/dev`\
`bin/console` opens an IRB session with the models loaded.

## Ride board
`/board` is the coordination screen: a queue of people waiting for a ride on the
left, one card per car in the middle, and a details/roster rail on the right.
Riders can be dragged between cars or click-to-seated, and `Auto-fill` seats
whoever is left.

Concepts:

- **Occurrence** — one `Event` row. Recurring events generate one row per week
  through `EventSeries`, so each week has its own rides message and roster.
- **Slot tabs** — the other events on the same date (e.g. Sunday School and
  Sunday Service). Create events in Discord with `/event create`.
- **Ride** — one person's participation in one occurrence: `role`
  (rider/driver), `status`, `seats`, `zone`, pickup spot, notes.
- **Zone** — coarse pickup area used for grouping and auto-fill. Edit the list in
  `Location::ZONES`; the defaults are placeholders from the design.
- **Clash** — "won't ride with", stored per pair of people so it carries across
  weeks rather than needing re-entry.

Auto-fill is greedy and deliberately dumb: it only fills empty seats, never
moves someone already seated, and respects clashes. `Closest zone first` prefers
a driver in the rider's zone; `Spread evenly` balances load across cars. Undo
reverses the last ten steps.

Everything on the board is a plain form POST, so it degrades to full page loads
without JavaScript.

## Tests
The board logic — auto-fill, clashes, seat counting, undo, CSV — is covered by
minitest. Each test runs in a transaction that is rolled back afterwards.

    rake test_setup   # once: create and migrate abid_test
    rake test

The Discord side is not tested; mocking discordrb is not worth the effort.
