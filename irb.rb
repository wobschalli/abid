require_relative 'config/environment'
require 'chronic'
require 'irb'

Abid.establish_connection
Abid.load_models

Chronic.time_class = Time.zone

puts "abid console (#{Abid.env}) — models loaded, Time.zone = #{Time.zone.name}"
binding.irb
