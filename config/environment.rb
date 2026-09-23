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

    # The path being rendered, so Layout can mark the active nav entry without
    # every page view having to thread it through its constructor. Thread-local
    # because Puma is threaded — same reason Time.zone is.
    def current_path
      Thread.current[:abid_current_path]
    end

    def current_path=(path)
      Thread.current[:abid_current_path] = path
    end

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

    # The URL prefix the dashboard is mounted under: '' at the domain root,
    # '/ridebot' when it lives at abidepurdue.com/ridebot so the root can hold
    # something else. config.ru mounts the app here (Rack::URLMap sets
    # SCRIPT_NAME), Sinatra's url()/to() prepend it, and the layout hands it to
    # the browser as data-root for the two scripts that build paths themselves.
    # Normalised: leading slash, no trailing slash, '/' means none.
    def root_path
      raw = ENV['ABID_ROOT_PATH'].to_s.strip
      path = raw.sub(%r{/+\z}, '')
      return '' if path.empty? || path == '/'

      path.start_with?('/') ? path : "/#{path}"
    end

    # The Distance Matrix key for the ride optimizer's travel times.
    #
    # ENV wins so a deploy can inject it, but the natural home is config.yml —
    # the gitignored, chmod-600 file the Discord token already lives in. A
    # missing key is not an error: the optimizer runs on distance estimates
    # until one exists, and starts fetching real times the day it appears.
    def google_maps_key
      # The suite must never reach Google. Every class that talks to it takes
      # an explicit `api_key:` for tests, but a default-constructed
      # TravelMatrix or Map inside a route or optimizer test would otherwise
      # find the production key in config.yml and spend live quota on
      # fixture coordinates — silently, since the tests still pass.
      return nil if env == 'test'

      key = ENV['GOOGLE_MAPS_KEY'].presence
      key ||= begin
        YAML.load_file('config.yml')['google_maps_key'] if File.exist?('config.yml')
      rescue StandardError
        nil
      end
      key.presence
    end

    # Basemap tiles for the route map.
    #
    # OpenStreetMap by default: no account, no token, no card on file, which
    # suits an app that otherwise takes no third-party runtime dependency.
    # Set MAPBOX_TOKEN to switch — nothing else changes. Mapbox needs a public
    # token shipped to the browser, so scope it to styles:read and restrict it
    # to your domain in the Mapbox console.
    def map_tiles
      token = ENV['MAPBOX_TOKEN'].to_s
      return OSM_TILES if token.empty?

      { url: "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=#{token}",
        attribution: '&copy; <a href="https://www.mapbox.com/about/maps/">Mapbox</a> ' \
                     '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>' }
    end

    OSM_TILES = {
      url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }.freeze

    # The Discord bot token. ENV, then config.yml, then the discord_infos row.
    #
    # config.yml is where the coordinator puts the token — it is the file the
    # example ships, the file the deploy runbook says to copy, and the file
    # that was updated after a token reset. Until now it was read only by
    # db/seeds.rb, which copied it into discord_infos once; the bot then read
    # the ROW, so a new token in the file changed nothing and the old bot kept
    # connecting from a restored database. The row stays as the last resort
    # for installs that never had the file.
    def discord_token
      ENV['DISCORD_TOKEN'].presence || discord_config['token'].presence || DiscordInfo.first&.token or
        raise 'no Discord token: set DISCORD_TOKEN, put discord.token in config.yml, or seed discord_infos'
    end

    # The `discord:` block of config.yml ({} when absent), read fresh each call
    # so a rewritten file is honoured on the next boot without a code change.
    def discord_config
      return {} unless File.exist?(root('config.yml'))

      (YAML.load_file(root('config.yml'))['discord'] || {}).to_h.transform_keys(&:to_s)
    rescue StandardError => e
      warn "config.yml unreadable: #{e.class}: #{e.message}"
      {}
    end

    def session_secret
      ENV['ABID_SESSION_SECRET'] || read_secret_file or
        raise 'no session secret: set ABID_SESSION_SECRET or create .session_secret'
    end

    # Pronounceable password. Users are created without anyone choosing a
    # password (Discord join, or a reaction from someone we have never seen),
    # and has_secure_password requires one. Duplicated in Bot and Bot::Setup
    # before this.
    def passgen
      require 'passgen'
      Passgen.generate(pronouncable: true, uppercase: false)
    end

    # ApplicationRecord first, explicitly. Sorting alone only worked by luck —
    # every model happened to sort after "application_record" until one did
    # not, and `class AcademicBreak < ApplicationRecord` then failed on an
    # uninitialized constant.
    def load_models
      base = root('models', 'application_record.rb')
      require base
      (Dir.glob(root('models', '*.rb')).sort - [base]).each { |model| require model }
    end

    # Nested so services/signup/*.rb is picked up too. Sorted so a namespace's
    # own file loads before the classes inside it.
    def load_services
      Dir.glob(root('services', '**', '*.rb')).sort.each { |service| require service }
    end

    def load_patches
      Dir.glob(root('patches', '*.rb')).sort.each { |patch| require patch }
    end

    # Components first: every view calls `include Components`, and views/*.rb
    # reference the component classes at class-definition time.
    #
    # In development config.ru loads these through Rack::Unreloader instead, so
    # they hot-reload. This exists for everything that is not the web server —
    # tests and the console — which previously could not render a view at all.
    def load_views
      # app.rb pulls this in for the web process; nothing else does.
      require 'phlex'
      Dir.glob(root('views', 'components', '*.rb')).sort.each { |view| require view }
      Dir.glob(root('views', '*.rb')).sort.each { |view| require view }
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
