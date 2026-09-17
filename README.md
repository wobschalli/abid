# abid
All the code for the Abide CF Discord bot

## Installation
Ensure you have ruby, bundler, npm, yarn, docker, and docker-compose, then run `yarn install` and `bundle install`. Afterwards run `rake -T` to initialize rake tasks

## Running
Start the database with `docker-compose`, then run the bot with `bin/bot`\
Web interface will be run seperately by running `bin/dev`

Copy `.env.local.example` to `.env.local` to point a local run at a separate
"beta" Discord application — `bin/bot` and `bin/dev` load it automatically.
See [DEPLOY.md](DEPLOY.md#running-a-beta-bot-locally).

## Deploying
Pushing to `main` builds a container image and restarts the stack (Postgres +
web + bot) on the server over SSH. Setup and operations live in
[DEPLOY.md](DEPLOY.md).
