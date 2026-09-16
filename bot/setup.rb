require_relative 'hfile'
require_relative 'bot'

class Bot
  class Setup
    # Discord roles that grant leader access on the dashboard. Missing roles are
    # tolerated — server admins are always leaders regardless.
    LEADER_ROLE_NAMES = ['Leaders', 'Coordinator'].freeze
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
    # Refreshes the channels we already know about. Deliberately does NOT create
    # a row for every channel it can see.
    #
    # It used to, which meant a bot invited to a 36-channel server got 36
    # Channel rows, and the sign-up composer then offered every one of them as
    # somewhere to post rides — #girlies-only included. Channels are declared in
    # config.yml, so the set of places this bot may post is an explicit
    # decision rather than a side effect of which server it was invited to.
    def setup_channels(server)
      #discordrb caching is dumb and needs to be done manually
      #after using this library, i can understand nietzsche more
      response = Discordrb::API::Server.channels(@bot.token, server.discord_id)
      JSON.parse(response.body).each do |channel_info|
        @bot.server(server.discord_id).add_channel(Discordrb::Channel.new(channel_info, @bot))
      end

      #now the cache is populated, so you can use it
      visible = @bot.server(server.discord_id).channels.index_by(&:id)

      Channel.where(server: server).find_each do |channel|
        live = visible[channel.discord_id]
        if live.nil?
          warn "channel ##{channel.name} (#{channel.discord_id}) is not visible to the bot"
          next
        end

        # Keep the name in step with Discord; the id is the identity.
        channel.update(name: live.name) if channel.name != live.name
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
      # A server without roles named exactly these used to crash the whole boot
      # here on `Role.find_by(...).discord_id` — NoMethodError on nil, before
      # the bot had done anything.
      leader_role_ids = LEADER_ROLE_NAMES.filter_map { |name| Role.find_by(name: name)&.discord_id }
      if leader_role_ids.empty?
        warn "no #{LEADER_ROLE_NAMES.join('/')} role on this server — only admins will be leaders"
      end

      @bot.server(server.discord_id).non_bot_members.each do |user|
        User.find_or_create_by(discord_id: user.id) do |u| #block runs on create only
          pass = passgen
          u.username = user.username
          u.name = user.display_name
          u.leader = user.permission?(:administrator) ||
                     leader_role_ids.any? { |role_id| user.role?(role_id) }
          u.password = pass
          u.password_confirmation = pass
        end
      end
    end
  end
end
