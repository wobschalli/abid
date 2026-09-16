require 'sinatra/activerecord/rake'
require 'rake/testtask'

namespace :db do
  task :load_config do
    require './app'
  end

  desc 'Load demo riders, drivers and events so the ride board has data'
  task :demo do
    ruby 'db/demo_seeds.rb'
  end

  desc 'Refine approximate location coordinates against OpenStreetMap'
  task :geocode do
    ruby 'db/geocode.rb'
  end
end

namespace :import do
  desc 'Import rider phone/residence/capacity from a form CSV (add ,apply to write)'
  task :riders, %i[path mode] do |_task, args|
    # Plain Ruby: ActiveSupport is not loaded until the require below.
    abort 'usage: rake import:riders[path/to/export.csv[,apply]]' if args[:path].to_s.empty?

    require_relative 'config/environment'
    Abid.establish_connection
    Abid.load_models
    Abid.load_services
    require_relative 'db/import_riders'

    Abid::ImportRiders.call(args[:path], apply: args[:mode] == 'apply')
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.warning = false
end

desc 'Create and migrate the test database, then run the tests'
task :test_setup do
  sh({ 'ABID_ENV' => 'test', 'RACK_ENV' => 'test' }, 'bundle exec rake db:create db:migrate')
end

task default: :test
