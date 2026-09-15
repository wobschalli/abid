require_relative 'scheduler'
require_relative 'setup'
require_relative 'hfile'

class Bot
  attr_reader :scheduler, :messenger

  # These used to be constants evaluated at class-definition time, which meant a
  # DB that wasn't up yet surfaced as a NoMethodError on nil during `require`.
  def self.info
    DiscordInfo.first
  end

  def self.test_server
    Server.find_by(name: 'Test')
  end

  def initialize(token = Abid.discord_token)
    @messenger = Messenger.new(token)
    @messenger.run
    Setup.new(bot)
    @scheduler = Scheduler.new(bot, @messenger)
    # Messenger handlers need the scheduler but cannot construct it — Bot builds
    # both, and Messenger is built first.
    @messenger.scheduler = @scheduler
  end

  # @return running bot [Discordrb::Commands::CommandBot]
  def bot
    @messenger.bot
  end

  def bot_schedule(event)
    @scheduler.schedule(event)
  end

  # @return pronouncable password [String]
  def passgen
    Passgen::generate(pronouncable: true, uppercase: false)
  end
end
