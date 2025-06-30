require 'rack/unreloader'
require 'sinatra/base'
require 'phlex-sinatra'
require 'phlex'
require 'discordrb'
require 'literal'
require 'tanuki_emoji'
require 'sequel'
require 'yaml'

dev = ENV['RACK_ENV'] == 'development'
puts "Running in #{ENV['RACK_ENV']} mode"

Unreloader = Rack::Unreloader.new(subclasses: %w'Sequel::Model Sinatra::Base Components', reolad: dev) { App.new }

class String
  def dasherize
    self.gsub!('_', '-')
    self.match(/[AZ]/)&.each do |cap|
      self.gsub!(cap, "-#{cap.downcase}")
    end
  end
end

wd = File.dirname(__FILE__)
#watch the app file
Unreloader.require File.join(wd, 'app.rb')
Dir.glob(File.join(wd, "views", "*.rb")).each do |view|
  Unreloader.require view
end
Dir.glob(File.join(wd, "views", "components", "*.rb")).each do |componenet|
  Unreloader.require componenet
end
Dir.glob(File.join(wd, "models", "*.rb")).each do |model|
  Unreloader.require model
end
Unreloader.require 'bot.rb'

#reload app on model changes
Unreloader.record_dependency(File.join(wd, 'models'), 'app.rb')

#reload views on components changes
Unreloader.record_dependency(File.join(wd, 'views', 'components'), File.join(wd, 'views'))

run dev ? Unreloader : App
