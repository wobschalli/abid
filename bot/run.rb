require_relative 'hfile'
require_relative 'scheduler'
require_relative 'messenger'
require_relative 'bot'

class Runner < Bot
  def initialize
    super(INFO.token)
  end
end

begin
  r = Runner.new
  loop do
    sleep(1.hour)
  end
rescue Interrupt
  r.bot.join
  exit
rescue => err
  puts err
  binding.irb
ensure
  r.bot.join
  exit
end
