require_relative 'hfile'
require_relative 'scheduler'
require_relative 'messenger'
require_relative 'bot'

class Runner < Bot
end

runner = nil

# SIGTERM is what a supervisor sends — systemd on restart, Docker on stop,
# `timeout` in a script. Ruby raises it as SignalException, which is not a
# StandardError, so it slipped past the `rescue` below, reached the `ensure`,
# and blocked forever in `bot.join` on a bot nobody had told to stop. The only
# way out was SIGKILL, which skips every at_exit hook.
#
# A Queue is the signal-safe way to do this: trap handlers run on the main
# thread with most operations forbidden, but pushing to a Queue is allowed, and
# `pop` blocks the boot thread until something arrives. It also replaces the
# old `loop { sleep 1.hour }`, so shutdown is immediate rather than whenever
# the current hour-long sleep happened to end.
signals = Queue.new
%w[INT TERM].each do |name|
  Signal.trap(name) { signals << name }
end

begin
  runner = Runner.new
  puts "running — send SIGINT or SIGTERM to stop"
  puts "received SIG#{signals.pop}, shutting down"
rescue => err
  # This used to drop into `binding.irb`, which hangs a headless/daemonised bot
  # forever instead of exiting and letting the supervisor restart it.
  warn "bot crashed: #{err.class}: #{err.message}"
  warn err.backtrace.join("\n") if err.backtrace
  exit 1
ensure
  # `r.bot.join` unconditionally used to raise NoMethodError on nil whenever boot
  # itself failed, masking the actual exception.
  bot = runner&.bot
  bot&.stop

  # Bounded join. discordrb's gateway thread can sit in a reconnect backoff that
  # ignores `stop`; exiting a few seconds late beats never exiting at all, and
  # the at_exit hooks that close the scheduler have already been registered.
  if bot && !Thread.new { bot.join }.join(10)
    warn 'gateway did not shut down within 10s — exiting anyway'
  end
end
