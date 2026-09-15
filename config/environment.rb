require 'erb'
require 'yaml'
require 'active_record'
require 'active_support'
require 'active_support/core_ext'
require 'tzinfo'

# Shared boot for both halves of the app (bot/ and the Sinatra web app).
# Previously the bot set the timezone and the web app didn't, so times written
# by one half were read back wrong by the other.
module Abid
  ROOT = File.expand_path('..', __dir__)

  # 'America/Indianapolis' is a deprecated tzinfo alias; this is the canonical id.
  TIME_ZONE = ENV.fetch('ABID_TZ', 'America/Indiana/Indianapolis')

  class << self
    attr_accessor :time_zone

    def env
      ENV['ABID_ENV'] || ENV['RACK_ENV'] || ENV['BOT_ENV'] || 'development'
    end

    def root(*parts)
      File.join(ROOT, *parts)
    end

    # config/database.yml holds the development defaults; anything set in the
    # environment wins. Kept in Ruby rather than ERB in the YAML because
    # sinatra-activerecord's rake tasks read that file themselves.
    def database_config
      return ENV['DATABASE_URL'] if ENV['DATABASE_URL'].present?

      config = YAML.safe_load_file(root('config', 'database.yml'), aliases: true).fetch(env) do
        raise "no '#{env}' section in config/database.yml"
      end

      config.merge(
        'username' => ENV['DB_USER'],
        'password' => ENV['DB_PASSWORD'],
        'host' => ENV['DB_HOST'],
        'port' => ENV['DB_PORT'],
        'database' => ENV['DB_NAME']
      ) { |_key, from_file, from_env| from_env.presence || from_file }
    end

    def establish_connection
      ActiveRecord::Base.establish_connection(database_config)
    end

    # Discord credentials. ENV wins so deploys don't need a seeded DB row, but we
    # still fall back to the discord_infos table for existing installs.
    def discord_token
      ENV['DISCORD_TOKEN'] || DiscordInfo.first&.token or
        raise 'no Discord token: set DISCORD_TOKEN or seed the discord_infos table'
    end

    def session_secret
      ENV['ABID_SESSION_SECRET'] || read_secret_file or
        raise 'no session secret: set ABID_SESSION_SECRET or create .session_secret'
    end

    def load_models
      Dir.glob(root('models', '*.rb')).sort.each { |model| require model }
    end

    def load_services
      Dir.glob(root('services', '*.rb')).sort.each { |service| require service }
    end

    def load_patches
      Dir.glob(root('patches', '*.rb')).sort.each { |patch| require patch }
    end

    private

    def read_secret_file
      path = root('.session_secret')
      File.exist?(path) ? File.read(path).strip : nil
    end
  end
end

# `Time.zone=` only sets a thread-local, so setting it at boot leaves Time.zone
# nil inside every Puma request thread. `Time.zone_default=` is the process-wide
# default that new threads inherit; set both so this process is correct too.
Abid.time_zone = ActiveSupport::TimeZone[Abid::TIME_ZONE] ||
                 raise("unknown timezone #{Abid::TIME_ZONE.inspect}")
Time.zone_default = Abid.time_zone
Time.zone = Abid.time_zone

# Moved off ActiveRecord::Base in Rails 7.
ActiveRecord.default_timezone = :utc

# Rails turns this on through its railtie; plain ActiveRecord does not, so
# datetime columns came back as bare UTC Times and every time on the board
# rendered four hours late (9:30 AM service showing as 1:30 PM).
ActiveRecord::Base.time_zone_aware_attributes = true
