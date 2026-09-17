# --- stage 1: build the css/js bundles ---------------------------------------
FROM node:20-slim AS assets

WORKDIR /build
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY public/css/application.css public/css/application.css
COPY src src
COPY views views
COPY webpack.config.js ./

ENV NODE_ENV=production
RUN npx @tailwindcss/cli -i ./public/css/application.css -o ./public/css/application.min.css -m \
 && npx webpack --config webpack.config.js --mode production

# --- stage 2: the ruby app ----------------------------------------------------
FROM ruby:3.4.2-slim AS app

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      libpq-dev \
      libxml2-dev \
      libyaml-dev \
      pkg-config \
      postgresql-client \
      zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /abid

# Gems first so dependency layers are cached across code-only changes.
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' \
 && bundle install --jobs 4 --retry 3 \
 && rm -rf /usr/local/bundle/cache

COPY . /abid
COPY --from=assets /build/public/css/application.min.css /abid/public/css/application.min.css
COPY --from=assets /build/public/js/application.min.js /abid/public/js/application.min.js

ENV RACK_ENV=production \
    BOT_ENV=production \
    LANG=C.UTF-8

EXPOSE 4455

ENTRYPOINT ["bin/docker-entrypoint"]
# Rack 3 dropped the `rackup` binary, so serve config.ru with Puma directly.
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:4455"]
