require_relative 'scheduler'
require_relative 'setup'
require_relative 'hfile'

class AppManager
  attr_reader :scheduler, :bot

  #load bot information
  INFO = DiscordInfo.first

  def initialize
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

  # @return pronouncable password [String]
  def passgen
    Passgen::generate(pronouncable: true, uppercase: false)
  end
end
