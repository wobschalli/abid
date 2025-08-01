require_relative 'scheduler'
require_relative 'setup'
require_relative 'hfile'

class Bot
  attr_reader :scheduler, :messenger

  #load bot information and test server
  INFO = DiscordInfo.first
  TEST = Server.find_by(name: 'Test')

  def initialize(token)
    @messenger = Messenger.new(INFO.token)
    @messenger.run
    Setup.new(bot)
    @scheduler = Scheduler.new(bot)
  end

  # @return running bot [Discordrb::Commands::CommandBot]
  def bot
    @messenger.bot
  end

  def debug
    binding.irb
  end

  def bot_schedule(event)
    @scheduler.schedule(event)
  end
end
