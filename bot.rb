require 'sequel'
require 'discordrb'
require 'literal'
require 'tanuki_emoji'
require 'yaml'

#make the yaml nice like rails does
temp = YAML.load_file 'config.yml'
CONFIG = {}
temp.each_key do |main_key|
  temp[main_key].each do |sub_key, value|
    CONFIG["#{main_key}.#{sub_key}"] = value
  end
end

class Discordrb::Bot
  def send(channel, message, tts:false, embeds:nil, attachments:nil, allowed_mentions:false, message_reference:nil, components:nil, timeout:nil)
    if timeout
      send_temporary_message channel, message, timeout, tts, embeds, attachments, allowed_mentions, message_reference, components
    else
      send_message channel, message, tts, embeds, attachments, allowed_mentions, message_reference, components
    end
  end
end

class Bot
  attr_accessor :bot

  def initialize
    @token = CONFIG['discord.token']
    @bot = Discordrb::Commands::CommandBot.new token: @token, prefix: "!", intents: [:server_messages, :server_members], ignore_bots: true
    set_commands
    # @bot_thread = Thread.new { @bot.run }
    at_exit { @bot.stop }
  end

  def send_sunday_rides(one=TanukiEmoji.find_by_alpha_code(':taxi:').codepoints, two=TanukiEmoji.find_by_alpha_code(':automobile:').codepoints)
    bot.send(CONFIG['test.general'],
      "@Riders react with #{one} if you would like a ride to sunday school at 9:30 or react with #{two} if you would like to a ride at 10:30!",
    )
  end

  def get_sunday_rides(message_id)
    @bot.channel(CONFIG['test.general']).load_message(message_id).all_reaction_users
  end

  def set_commands
    bot.command :user do |event|
      event.user.name
    end
  end

  # @param server id [Integer]
  # @return array of roles [Array<Discordrb::Role>]
  def get_all_roles(server=CONFIG['servers.abide'])
    bot.server(server).roles
  end

  # @param server id [Integer]
  # @return array of users [Array<Discordrb::Member>]
  def get_all_users(server=CONFIG['servers.general'])
    bot.server(server).non_bot_members
  end

  def run
    @bot.run
  end
end

BOT = Bot.new
BOT.run
