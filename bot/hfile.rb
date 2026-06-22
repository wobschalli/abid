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

base_dir = File.dirname(__dir__.to_s)
db_config_path = File.join(base_dir, 'config', 'database.yml')
db_config = YAML.safe_load_file(db_config_path, aliases: true)
current_env = ENV.fetch('BOT_ENV', 'development')

ActiveRecord::Base.establish_connection(db_config[current_env])

#include activemodel models for interacting with the database
models_paths = Dir.glob(File.join(base_dir, 'models', '*.rb'))
models_paths.each do |model|
  require_relative model
end

#include all patches to relevant classes because discordrb is lowk dumb
patches_paths = Dir.glob(File.join(base_dir, 'patches', '*.rb'))
patches_paths.each do |patch|
  require_relative patch
end

#get the map class
map_path = File.join(base_dir, 'map', 'map.rb')
require_relative map_path

# Set the application timezone so all parsed/created times are consistent.
Time.zone = TZInfo::Timezone.get('America/Indiana/Indianapolis')
Chronic.time_class = Time.zone
ActiveRecord.default_timezone = :utc
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.time_zone_aware_types = [:datetime]

#load bot helper classes after models, patches, and timezone are ready
bot_classes_paths = Dir.glob(File.join(base_dir, 'bot', '*.rb'))
bot_classes_paths.each do |bot_file|
  require_relative bot_file unless bot_file.end_with?('run.rb')
end
