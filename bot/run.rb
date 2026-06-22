require_relative 'hfile'
require_relative 'bot'

class Runner < Bot
  def initialize
    super(INFO.token)
  end
end

begin
  r = Runner.new

  # Set up signal handlers for clean shutdown
  trap('INT') do
    puts "\nShutting down bot..."
    r.bot.stop
    exit(0)
  end

  trap('TERM') do
    puts "\nTerminating bot..."
    r.bot.stop
    exit(0)
  end

  loop do
    sleep(1)
  end
rescue Interrupt
  puts "Interrupt received"
  r.bot.stop
  exit(0)
rescue => err
  puts err
  puts err.backtrace.join(%Q{\n})
  binding.irb
ensure
  begin
    r.bot.stop
  rescue
  end
  exit(0)
end
