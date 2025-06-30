require 'rack/unreloader'
require 'yaml'

Unreloader = Rack::Unreloader.new(subclasses: %w'Sequel::Model', reolad: true)

Dir.glob(File.join(Dir.pwd, "models", "*.rb")).each do |model|
  Unreloader.require model
end
# Unreloader.require 'bot.rb'

class String
  def dasherize
    self.gsub('_', '-')
    self.match(/[AZ]/).each do |cap|
      self.gsub(cap, "-#{cap.downcase}")
    end
  end
end

temp = YAML.load_file 'config.yml'
CONFIG = {}
temp.each_key do |main_key|
  temp[main_key].each do |sub_key, value|
    CONFIG["#{main_key}.#{sub_key}"] = value
  end
end

binding.irb
