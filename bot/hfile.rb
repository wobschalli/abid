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

ActiveRecord::Base.establish_connection(YAML.load_file(File.join(File.dirname(__dir__), 'config', 'database.yml'), aliases: true)[ENV.fetch('BOT_ENV', 'development')])

#include activemodel models for interacting with the database
Dir.glob(File.join(File.dirname(__dir__), 'models', '*.rb')).each do |model|
  require_relative model
end

#include all patches to relevant classes because discordrb is lowk dumb
Dir.glob(File.join(File.dirname(__dir__), 'patches', '*.rb')).each do |patch|
  require_relative patch
end

#get the map class
require_relative File.join(File.dirname(__dir__), 'map', 'map.rb')

# Set the application timezone so all parsed/created times are consistent.
Time.zone = TZInfo::Timezone.get('America/Indiana/Indianapolis')
Chronic.time_class = Time.zone
ActiveRecord.default_timezone = :utc
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.time_zone_aware_types = [:datetime]

#load bot helper classes after models, patches, and timezone are ready
Dir.glob(File.join(File.dirname(__dir__), 'bot', '*.rb')).each do |bot_file|
  require_relative bot_file unless bot_file.end_with?('run.rb')
end
