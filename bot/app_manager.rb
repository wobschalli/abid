require_relative 'bot'
require_relative 'abide_event_manager/scheduler/scheduler'
require_relative 'setup'

class AppManager
  attr_reader :scheduler, :bot

  #load bot information
  INFO = DiscordInfo.first

  def initialize
    if INFO.nil?
      abort "CRITICAL: No configuration found in DiscordInfo table. Run database seeds using config.yml (if you don't have it, contact Ian)."
    end
    @bot = Bot.new(INFO.token)
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
