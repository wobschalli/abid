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

ActiveRecord::Base.establish_connection(YAML.load_file(File.join(Dir.pwd, '..', 'config', 'database.yml'), aliases: true)[ENV.fetch('BOT_ENV', 'development')])

#include activemodel models for interacting with the database
Dir.glob(File.join(Dir.pwd, '..', 'models', '*.rb')).each do |model|
  require_relative model
end

#include all patches to relevant classes because discordrb is lowk dumb
Dir.glob(File.join(Dir.pwd, '..', 'patches', '*.rb')).each do |patch|
  require_relative patch
end

#get the map class
require_relative File.join(Dir.pwd, '..', 'map', 'map.rb')

#set timezone to local
Time.zone = TZInfo::Timezone.get('America/Indianapolis')
Chronic.time_class = Time.zone
