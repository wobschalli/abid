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
    start_job_worker
  end

  # que's worker threads, in this process rather than a separate one — the box
  # has ~900 MB to spare and the bot is already the long-lived process. Only
  # with ABID_JOBS=1, and a failure to start is logged, never fatal: the bot's
  # real job is the sign-up posts, and those do not go through que.
  def start_job_worker
    return unless Abid.jobs_enabled?

    @job_locker = Que::Locker.new(worker_priorities: [nil])
    puts 'job worker started (que)'
  rescue StandardError => e
    warn "job worker failed to start — jobs will wait: #{e.class}: #{e.message}"
  end

  def stop_job_worker
    @job_locker&.stop!
  rescue StandardError => e
    warn "job worker stop: #{e.class}: #{e.message}"
  end

  # @return running bot [Discordrb::Commands::CommandBot]
  def bot
    @messenger.bot
  end

  # `bot_schedule` lived here. Scheduler no longer registers per-event jobs — it
  # polls for due sign-up posts instead — so there is nothing to call.

  # @return pronouncable password [String]
  def passgen
    Passgen::generate(pronouncable: true, uppercase: false)
  end
end
