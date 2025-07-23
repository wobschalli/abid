require 'rack/unreloader'
require 'yaml'
# require 'active_record'
require 'active_record'
require 'active_model'
require 'chronic'
require 'rufus-scheduler'

Dir.glob(File.join(Dir.pwd, "models", "*.rb")).each do |model|
  require_relative model
end

class String
  def dasherize
    self.gsub('_', '-')
    self.match(/[AZ]/).each do |cap|
      self.gsub(cap, "-#{cap.downcase}")
    end
  end
end

class DateTime
  def parseable
    self.strftime '%Y-%m-%d %H:%M:%S'
  end
end

temp = YAML.load_file 'config.yml'
CONFIG = {}
temp.each_key do |main_key|
  temp[main_key].each do |sub_key, value|
    CONFIG["#{main_key}.#{sub_key}"] = value
  end
end

ActiveRecord::Base.establish_connection(YAML.load_file('./config/database.yml', aliases: true)['development'])
binding.irb
