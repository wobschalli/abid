require 'discordrb'
require 'literal'
require 'tanuki_emoji'
require 'yaml'
require 'active_record'
require 'active_model'
require 'active_support'
require 'chronic'
require 'rufus-scheduler'
require 'tzinfo'
require 'passgen'
require 'http'

# Shared boot: env, timezone, database config. This used to be inline here with
# Dir.pwd-relative paths, which only resolved because bin/bot cd's into bot/
# first — running `ruby bot/run.rb` from the repo root blew up.
require_relative '../config/environment'

Abid.establish_connection
Abid.load_models

#get the map class — services/ depends on it, so it has to come first
require_relative '../map/map'

# The web process loads these through config.ru's Unreloader globs; the bot had
# no equivalent, so anything under services/ was a NameError in production only.
Abid.load_services

#include all patches to relevant classes because discordrb is lowk dumb
Abid.load_patches

Chronic.time_class = Time.zone
