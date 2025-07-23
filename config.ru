require 'rack/unreloader'
require 'sinatra/base'
require 'discordrb'
require 'literal'
require 'tanuki_emoji'
require 'yaml'
require 'sinatra/activerecord'

dev = ENV['RACK_ENV'] == 'development'
puts "Running in #{ENV['RACK_ENV']} mode"

Unreloader = Rack::Unreloader.new(subclasses: %w'ActiveRecord::Migration ActiveModel::Validations ActiveModel::Model ActiveModel::Callbacks Sinatra::Base', reolad: dev) { App.new }

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
