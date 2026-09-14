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
    def env
      ENV['ABID_ENV'] || ENV['RACK_ENV'] || ENV['BOT_ENV'] || 'development'
    end

    def root(*parts)
      File.join(ROOT, *parts)
    end

    def database_config
      raw = ERB.new(File.read(root('config', 'database.yml'))).result
      config = YAML.safe_load(raw, aliases: true).fetch(env) do
        raise "no '#{env}' section in config/database.yml"
      end
      config.compact
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

Time.zone = TZInfo::Timezone.get(Abid::TIME_ZONE)
ActiveRecord::Base.default_timezone = :utc
