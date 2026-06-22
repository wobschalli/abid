require_relative 'hfile'
require_relative 'app_manager'

class Runner < AppManager
  def initialize
    super()
  end
end

begin
  r = Runner.new

  # Set up signal handlers for clean shutdown
  trap('INT') do
    puts "\nShutting down bot..."
    r.client.stop
    exit(0)
  end

  trap('TERM') do
    puts "\nTerminating bot..."
    r.client.stop
    exit(0)
  end

  loop do
    sleep(1)
  end
rescue Interrupt
  puts "Interrupt received"
  r.client.stop
  exit(0)
rescue => err
  puts err
  puts err.backtrace.join(%Q{\n})
  binding.irb
ensure
  begin
    r.client.stop
  rescue
  end
  exit(0)
end
