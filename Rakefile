require 'sinatra/activerecord/rake'

namespace :db do
  task :load_config do
    require './app'
  end

  desc 'Load demo riders, drivers and events so the ride board has data'
  task :demo do
    ruby 'db/demo_seeds.rb'
  end
end
