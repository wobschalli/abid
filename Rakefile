require 'sinatra/activerecord/rake'
require 'rake/testtask'

namespace :db do
  task :load_config do
    require './app'
  end

  desc 'Load demo riders, drivers and events so the ride board has data'
  task :demo do
    ruby 'db/demo_seeds.rb'
  end

  desc 'Verify every location against Google (Nominatim fallback), recording how precisely it resolved'
  task :verify_locations do
    ruby 'db/geocode.rb'
  end

  # The old name, kept so existing habits and docs still work.
  task geocode: :verify_locations

  desc "Make the database match Abide's real weekly schedule (add [apply] to write)"
  task :schedule, [:mode] do |_task, args|
    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models
    Abid.load_services
    require_relative 'db/schedule'

    Abid::Schedule.call(apply: args[:mode] == 'apply')
  end

  desc 'Remove everything db:demo invented, keeping the real server data (add [apply] to write)'
  task :drop_demo, [:mode] do |_task, args|
    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models
    Abid.load_services
    require_relative 'db/drop_demo'

    Abid::DropDemo.call(apply: args[:mode] == 'apply')
  end
end

namespace :import do
  desc 'Import rider phone/residence/capacity from a form CSV (add ,apply to write)'
  task :riders, %i[path mode] do |_task, args|
    # Plain Ruby: ActiveSupport is not loaded until the require below.
    abort 'usage: rake import:riders[path/to/export.csv[,apply]]' if args[:path].to_s.empty?

    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models
    Abid.load_services
    require_relative 'db/import_riders'

    Abid::ImportRiders.call(args[:path], apply: args[:mode] == 'apply')
  end

  desc 'Import the census CSV: same details, and marks everyone who answered as Active'
  task :census, %i[path mode] do |_task, args|
    abort 'usage: rake import:census[path/to/census.csv[,apply]]' if args[:path].to_s.empty?

    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models
    Abid.load_services
    require_relative 'db/import_riders'

    # Filling in the census is the statement "I am part of this fellowship this
    # year", which is exactly what Active means. The rides sheet is not — a
    # one-off passenger can appear on it — so only this task sets the flag.
    Abid::ImportRiders.call(args[:path], apply: args[:mode] == 'apply', mark_active: true)
  end
end

namespace :snipes do
  desc 'Make a channel THE snipes channel, by Discord channel id (moves the role if another channel had it)'
  task :channel, [:discord_id] do |_task, args|
    abort 'usage: rake snipes:channel[DISCORD_CHANNEL_ID]' if args[:discord_id].to_s !~ /\A\d+\z/

    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models

    channel = Channel.assign_purpose!('snipes', discord_id: args[:discord_id].to_i)
    puts "snipes channel: ##{channel.name} (#{channel.discord_id})"
    puts 'now: rake snipes:post — and make sure the bot has Manage Messages there'
  end

  desc 'Post the opt-out message with its two buttons (or refresh it if already posted)'
  task :post do
    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models

    channel = Channel.snipes or abort 'no snipes channel yet — run rake snipes:channel[ID] first'
    # An outbox flag, not a second gateway connection: the running bot posts
    # it on its next tick. Two bots on one token is the one thing this project
    # must never do.
    channel.update!(notice_requested_at: Time.zone.now)
    puts "requested — the bot posts (or refreshes) the message in ##{channel.name} within 30 seconds"
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.warning = false
end

desc 'Create and migrate the test database, then run the tests'
task :test_setup do
  sh({ 'ABID_ENV' => 'test', 'RACK_ENV' => 'test' }, 'bundle exec rake db:create db:migrate')
end

task default: :test
