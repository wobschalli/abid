require_relative 'hfile'
require_relative 'bot'

class Bot
  class Setup
    # @param bot [Discordrb::Commands::CommandBot]
    def initialize(bot)
      @bot = bot
      server = Server.find_by(name: 'Abide')
      setup_channels(server)
      setup_emojis(server)
      setup_roles(server)
      setup_users(server)
    end

  # @return pronouncable password [String]
  def passgen
    Passgen::generate(pronouncable: true, uppercase: false)
  end

    private
    # @param server [Server]
    # @return array of channels [Array<Discordrb::Channel>]
    def setup_channels(server)
      #discordrb caching is dumb and needs to be done manually
      #after using this library, i can understand nietzsche more
      response = Discordrb::API::Server.channels(@bot.token, server.discord_id)
      JSON.parse(response.body).each do |channel_info|
        @bot.server(server.discord_id).add_channel(Discordrb::Channel.new(channel_info, @bot))
      end

      #now the cache is populated, so you can use it
      @bot.server(server.discord_id).channels.each do |channel|
        Channel.find_or_create_by(discord_id: channel.id) do |c|
          c.name = channel.name
          c.server = server
        end
      end
    end

    # @param server [Server]
    # @return array of emojis [Array<Discordrb::Emoji>]
    def setup_emojis(server)
      @bot.server(server.discord_id).emojis.each do |id, emoji|
        Emoji.find_or_create_by(discord_id: id) do |e|
          e.name = emoji.name
          e.server = server
        end
      end
    end

    # @param server [Server]
    # @return array of roles [Array<Discordrb::Role>]
    def setup_roles(server)
      @bot.server(server.discord_id).roles.each do |role|
        Role.find_or_create_by(discord_id: role.id) do |r|
          r.name = role.name
          r.admin = role.permissions.administrator
        end
      end
    end

    # @param server [Server]
    # @return array of users [Array<Discordrb::Member>]
    def setup_users(server)
      @bot.server(server.discord_id).non_bot_members.each do |user|
        User.find_or_create_by(discord_id: user.id) do |u| #block runs on create only
          pass = passgen
          leader = Role.find_by(name: 'Leaders').discord_id
          coordinator = Role.find_by(name: 'Coordinator').discord_id
          u.username = user.username
          u.name = user.display_name
          u.leader = user.permission?(:administrator) || user.role?(leader) || user.role?(coordinator)
          u.password = pass
          u.password_confirmation = pass
        end
      end
    end
  end
end
