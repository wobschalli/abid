require_relative 'hfile'
require_relative 'scheduler'
require_relative 'messenger'
require_relative 'bot'

class Runner < Bot
end

runner = nil

begin
  runner = Runner.new
  loop { sleep(1.hour) }
rescue Interrupt
  puts 'shutting down'
rescue => err
  # This used to drop into `binding.irb`, which hangs a headless/daemonised bot
  # forever instead of exiting and letting the supervisor restart it.
  warn "bot crashed: #{err.class}: #{err.message}"
  warn err.backtrace.join("\n") if err.backtrace
  exit 1
ensure
  # `r.bot.join` unconditionally used to raise NoMethodError on nil whenever boot
  # itself failed, masking the actual exception.
  runner&.bot&.join
end
