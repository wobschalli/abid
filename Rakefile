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
