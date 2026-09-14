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

#include all patches to relevant classes because discordrb is lowk dumb
Abid.load_patches

#get the map class
require_relative '../map/map'

Chronic.time_class = Time.zone
