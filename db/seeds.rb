require 'yaml'
require 'active_record'

#have to require models manually
require_relative '../models/application_record'
require_relative '../models/channel'
require_relative '../models/discord_info'
require_relative '../models/emoji'
require_relative '../models/event'
require_relative '../models/location'
require_relative '../models/role'
require_relative '../models/server'
require_relative '../models/user'

# Real geography first: everything below this point needs config.yml and bails
# without it, but the locations do not and are needed on every machine.
require_relative 'locations'
Abid::Locations.seed!
puts "seeded #{Abid::Locations.count} locations"

begin
  config = YAML.load_file('config.yml')
rescue Errno::ENOENT
  puts "config.yml was not found"
  exit
end

ABIDE_SERVER = Server.find_or_create_by name: 'Abide', discord_id: config.dig('servers', 'abide')

config['channels'].each do |name, id|
  Channel.find_or_create_by name: name, discord_id: id, server: ABIDE_SERVER
end

config['emojis'].each do |name, id|
  Emoji.find_or_create_by name: name, discord_id: id, server: ABIDE_SERVER
end

TEST_SERVER = Server.find_or_create_by name: 'Test', discord_id: config.dig('servers', 'test')
Channel.find_or_create_by name: 'general', discord_id: config.dig('test', 'general'), server: TEST_SERVER

DiscordInfo.find_or_create_by token: config.dig('discord', 'token'), app_id: config.dig('discord', 'app_id'), public_key: config.dig('discord', 'public_key')

# Locations moved to db/locations.rb, seeded above.

#data privacy or something
config['users'].each do |user, data|
  User.find_or_create_by data
end
