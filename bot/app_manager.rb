require_relative 'bot'
require_relative 'abide_event_manager/scheduler/scheduler'
require_relative 'setup'

class AppManager
  attr_reader :scheduler, :bot

  #load bot information
  # DISCORD_TOKEN overrides the seeded token so you can point a local run at a
  # separate "beta" Discord application while production keeps using the DB row.
  def self.token
    env_token = ENV['DISCORD_TOKEN'].to_s.strip
    unless env_token.empty?
      puts "Using DISCORD_TOKEN from the environment (beta bot)"
      return env_token
    end

    info = DiscordInfo.first
    if info.nil?
      abort "CRITICAL: No configuration found in DiscordInfo table. Run database seeds using config.yml (if you don't have it, contact Ian), or set DISCORD_TOKEN."
    end
    info.token
  end

  def initialize
    @bot = Bot.new(self.class.token)
    @bot.manager = self
    @bot.run
    Setup.new(client)
    @scheduler = Scheduler.new(@bot)
  end

  # @return running map_client [Discordrb::Commands::CommandBot]
  def client
    @bot.client
  end

  def debug
    binding.irb
  end

  def bot_schedule(event)
    @scheduler.schedule(event)
  end
end
