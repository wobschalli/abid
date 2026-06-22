class AppManager
  class Setup
    # @param client [Discordrb::Commands::CommandBot]
    def initialize(client)
      @client = client

      response = Discordrb::API::User.servers(@client.token)
      connected_servers = JSON.parse(response.body).map { |s| s['id'].to_i }

      Server.all.each do |server|
        if connected_servers.include?(server.discord_id)
          begin
            setup_channels(server)
            setup_emojis(server)
            setup_roles(server)
            setup_users(server)
          rescue => e
            puts "Warning: Could not configure server '#{server.name}' (#{e.message})"
          end
        else
          puts "Bot is not in server '#{server.name}'. Removing from database."
          server.destroy
        end
      end
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
      response = Discordrb::API::Server.channels(@client.token, server.discord_id)
      JSON.parse(response.body).each do |channel_info|
        @client.server(server.discord_id).add_channel(Discordrb::Channel.new(channel_info, @client))
      end

      #now the cache is populated, so you can use it
      @client.server(server.discord_id).channels.each do |channel|
        Channel.find_or_create_by(discord_id: channel.id) do |c|
          c.name = channel.name
          c.server = server
        end
      end
    end

    # @param server [Server]
    # @return array of emojis [Array<Discordrb::Emoji>]
    def setup_emojis(server)
      @client.server(server.discord_id).emojis.each do |id, emoji|
        Emoji.find_or_create_by(discord_id: id) do |e|
          e.name = emoji.name
          e.server = server
        end
      end
    end

    # @param server [Server]
    # @return array of roles [Array<Discordrb::Role>]
    def setup_roles(server)
      @client.server(server.discord_id).roles.each do |role|
        Role.find_or_create_by(discord_id: role.id) do |r|
          r.name = role.name
          r.admin = role.permissions.administrator
        end
      end
    end

    # @param server [Server]
    # @return array of users [Array<Discordrb::Member>]
    def setup_users(server)
      @client.server(server.discord_id).non_bot_members.each do |user|
        pass = passgen
        leader = Role.find_by(name: 'Leaders')&.discord_id
        coordinator = Role.find_by(name: 'Coordinator')&.discord_id

        is_leader = user.permission?(:administrator) ||
                    (leader && user.role?(leader)) ||
                    (coordinator && user.role?(coordinator))

        User.find_or_create_by(discord_id: user.id) do |u| #block runs on create only
          u.username = user.username
          u.name = user.display_name
          u.leader = is_leader
          u.password = pass
        end
      end
    end
  end
end
