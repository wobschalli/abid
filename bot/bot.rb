require_relative 'abide_event_manager/helpers/naming_helper.rb'
require_relative 'abide_event_manager/helpers/modal_helper.rb'
require_relative 'abide_event_manager/helpers/draft_helper.rb'
require_relative 'abide_event_manager/event_draft'

class Bot
  attr_reader :client, :map, :token
  attr_accessor :manager

  def initialize(token)
    @token = token
    @map = Map.new
    @client = Discordrb::Commands::CommandBot.new token: @token, prefix: "!", intents: [:server_messages, :server_members, :direct_messages], ignore_bots: true
    @client.init_cache
    register_commands
    set_button_handlers
    set_select_handlers
    set_modal_handlers
    set_commands
    set_event_handlers
    at_exit do
      @client.stop
    end
  end

  def dm_mods(message)
    [:dm_ian, :dm_alan, :dm_bfm].map do |send_msg|
      send(send_msg, message)
    end
  end

  def dm_ian(message)
    ian = User.find_by(name: 'ian')&.discord_id
    return unless ian
    @client.user(ian).dm(message)
  end

  def dm_alan(message)
    alan = User.find_by(name: 'alan')&.discord_id
    return unless alan
    @client.user(alan).dm(message)
  end

  def dm_bfm(message)
    bfm = User.find_by(name: 'bfm')&.discord_id
    return unless bfm
    @client.user(bfm).dm(message)
  end

  def get_all_roles(server)
    @client.server(server).roles
  end

  def run(background=true)
    @client.run(background)
    true
  end

  def send(channel, message, tts:false, embeds:nil, attachments:nil, allowed_mentions:false, message_reference:nil, components:nil, timeout:nil)
    @client.send(channel, message, tts: tts, embeds: embeds, attachments: attachments, allowed_mentions: allowed_mentions, message_reference: message_reference, components: components, timeout: timeout)
  end

  private

  def register_commands
    response = Discordrb::API::User.servers(client.token)
    connected_servers = JSON.parse(response.body).map { |s| s['id'].to_i }

    Server.all.each do |server|
      if connected_servers.include?(server.discord_id)
        begin
          client.register_application_command(:login, 'send a login code', server_id: server.discord_id)

          client.register_application_command(:event, 'event commands', server_id: server.discord_id) do |cmd|
            cmd.subcommand(:list, 'list all events') do |sub|
              sub.string(:status, 'filter by status (optional)', required: false, choices: { unpublished: 'unpublished', scheduled: 'scheduled', active: 'active', completed: 'completed', cancelled: 'cancelled' })
            end
            cmd.subcommand(:create, 'create a draft event') do |sub|
              sub.string(:name, 'event name', required: true)
            end
            cmd.subcommand(:show, 'show details of an event') do |sub|
              sub.string(:name, 'event name', required: true, autocomplete: true)
            end
            cmd.subcommand(:delete, 'permanently delete an unpublished event') do |sub|
              sub.string(:name, 'event name', required: true, autocomplete: true)
            end
            cmd.subcommand(:nuke, 'delete ALL events (owner only)')
          end
        rescue => e
          puts "Warning: Could not register cmds for #{server.name} - #{e.message}"
        end
      end
    end
  end

  def set_commands
    client.command :user do |event|
      event.user.name
    end

    client.application_command(:hello) do |event|
      return event.respond(content: 'Hello there!')
    end

    client.autocomplete(:name) do |event|
      search = event.options['name'].to_s.downcase
      events = Event.where("LOWER(name) LIKE ?", "%#{search}%").limit(25)
      choices = events.map { |e| { name: e.name || "Untitled_#{e.id}", value: e.id.to_s } }
      event.respond(choices: choices)
    end

    client.application_command(:event).subcommand(:list) do |event|
      user = User.find_by(discord_id: event.user.id)
      status_filter = event.options['status']

      events = if status_filter
        if status_filter == 'unpublished' && !(user&.leader || user&.coordinator?)
          return event.respond(content: 'Only leaders and coordinators can view unpublished events.', ephemeral: true)
        end
        Event.where(status: status_filter.to_sym)
      else
        Event.published
      end.limit(25)

      if events.empty?
        event.respond(content: "No events found.", ephemeral: true)
      else
        desc = events.map { |e| "**#{e.name || "Untitled_#{e.id}"}** - #{e.status}" }.join("\n")
        event.respond(content: "Events:\n#{desc}")
      end
    end

    client.application_command(:event).subcommand(:delete) do |event|
      user = User.find_by(discord_id: event.user.id)
      return event.respond(content: 'You are not allowed to do that!', ephemeral: true) unless user&.leader || user&.coordinator?
      evt = Event.find_by(id: event.options['name'].to_i)
      return event.respond(content: 'Event not found.', ephemeral: true) unless evt
      return event.respond(content: 'Only unpublished events can be deleted with this command.', ephemeral: true) unless evt.unpublished?
      name = evt.name || "Untitled_#{evt.id}"
      evt.destroy
      event.respond(content: "Event **#{name}** has been permanently deleted.", ephemeral: true)
    end

    client.application_command(:event).subcommand(:create) do |event|
      user = User.find_by(discord_id: event.user.id)
      return event.respond(content: 'You are not allowed to do that!', ephemeral: true) unless user&.leader || user&.coordinator?

      base_name = event.options['name'].strip
      name = generate_unique_event_name(base_name)
      draft = EventDraft.create(organizer_id: user.id, name: name)

      event.respond(content: "Let's build your event!", embeds: [event_dashboard_embed(draft)]) do |_, view|
        render_builder_components(view, draft)
      end
    end

    client.application_command(:event).subcommand(:show) do |event|
      user = User.find_by(discord_id: event.user.id)
      return event.respond(content: 'You are not allowed to do that!', ephemeral: true) unless user&.leader || user&.coordinator?
      evt = Event.find_by(id: event.options['name'].to_i)
      return event.respond(content: 'Event not found.', ephemeral: true) unless evt

      can_edit = user.leader || user.coordinator? || (evt.organizer_id && evt.organizer_id == user.id)
      if can_edit
        event.respond content: '', embeds: [event_dashboard_embed(evt)] do |_, view|
          render_event_management_components(view, evt)
        end
      else
        event.respond content: '', embeds: [event_dashboard_embed(evt)]
      end
    end

    client.application_command(:event).subcommand(:nuke) do |event|
      return event.respond(content: 'You are not authorized to use this command.', ephemeral: true) unless event.user.id == 434430979075997707
      Event.destroy_all
      event.respond(content: 'All events have been destroyed.', ephemeral: true)
    end

    client.application_command(:login) do |event|
      user = User.find_by(discord_id: event.user.id)
      return event.respond(content: 'You are not able to do that!', ephemeral: true) unless user&.leader
      handle_login_code(user)
      event.respond(content: 'Your login code has been sent', ephemeral: true)
    end

    client.application_command(:debug) do |event|
      if User.find_by(discord_id: event.user.id)&.leader
        event.defer
        debug
        event.send_message(content: 'Your debug session is finished', ephemeral: true)
      else
        dm_ian("an unauthorized user (#{event.user.username} | #{event.user.id}) attempted to use debug")
        event.respond(content: 'You do not have the proper authentication to perform this action!')
      end
    end
  end

  def set_button_handlers
    client.button custom_id: /event_edit_basics_(.+)/ do |event|
      with_draft_or_event(event) { |draft| show_edit_basics_modal(event, draft) }
    end

    client.button custom_id: /event_edit_timing_(.+)/ do |event|
      with_draft_or_event(event) { |draft| show_edit_timing_modal(event, draft) }
    end

    client.button custom_id: /event_edit_reactions_(.+)/ do |event|
      with_draft_or_event(event) { |draft| show_edit_reactions_modal(event, draft) }
    end

    client.button custom_id: /event_publish_(.+)/ do |event|
      with_draft(event) { |draft| publish_draft(event, draft) }
    end

    client.button custom_id: /event_save_unpublished_(.+)/ do |event|
      with_draft(event) { |draft| save_draft_as_unpublished(event, draft) }
    end

    client.button custom_id: /event_discard_(.+)/ do |event|
      with_draft(event) { |draft| discard_draft(event, draft) }
    end

    client.button custom_id: /event_unpublish_(\d+)/ do |event|
      with_event(event) { |evt| unpublish_event(event, evt) }
    end

    client.button custom_id: /event_republish_(\d+)/ do |event|
      with_event(event) { |evt| republish_event(event, evt) }
    end

    client.button custom_id: /event_cancel_(\d+)/ do |event|
      with_event(event) { |evt| cancel_event(event, evt) }
    end

    client.button custom_id: /event_delete_(\d+)/ do |event|
      with_event(event) { |evt| delete_event(event, evt) }
    end

    client.button custom_id: /event_duplicate_(\d+)/ do |event|
      with_event(event) { |evt| duplicate_event(event, evt) }
    end
  end

  def set_select_handlers
    client.select_menu custom_id: /event_set_channel_(.+)/ do |event|
      with_draft_or_event(event) do |draft|
        channel_id = event.values.first.to_i
        channel = Channel.find_by(discord_id: channel_id)
        draft.channel = channel if channel
        refresh_dashboard(event, draft)
      end
    end
  end

  def set_modal_handlers
    client.modal_submit custom_id: /event_modal_basics_(.+)/ do |event|
      with_draft_or_event(event) { |draft| handle_edit_basics(event, draft) }
    end

    client.modal_submit custom_id: /event_modal_timing_(.+)/ do |event|
      with_draft_or_event(event) { |draft| handle_edit_timing(event, draft) }
    end

    client.modal_submit custom_id: /event_modal_reactions_(.+)/ do |event|
      with_draft_or_event(event) { |draft| handle_edit_reactions(event, draft) }
    end
  end

  def set_event_handlers
    @client.member_join do |event|
      handle_member_join event
    end

    @client.member_leave do |event|
      handle_member_leave event
    end
  end

  # ---------------------------------------------------------------------------
  # Other handlers
  # ---------------------------------------------------------------------------

  def handle_login_code(user)
    code = passgen
    user.update(password: code, password_confirmation: code)
    @client.user(user.discord_id).dm("Here is your login code: #{code}")
  end

  def handle_member_join(event)
    return unless Server.find_by(name: 'Abide')&.discord_id == event.server.id

    leader_role_id = Role.find_by(name: 'Leaders')&.discord_id
    coordinator_role_id = Role.find_by(name: 'Coordinator')&.discord_id

    User.find_or_create_by(discord_id: event.member.id) do |user|
      pass = passgen
      user.username = event.member.username
      user.name = event.member.display_name
      user.leader = event.member.permission?(:administrator) ||
                     (leader_role_id && event.member.role?(leader_role_id)) ||
                     (coordinator_role_id && event.member.role?(coordinator_role_id))
      user.password = pass
      user.password_confirmation = pass
    end
  end

  def handle_member_leave(event)
    return unless Server.exists?(discord_id: event.server.id)
    User.find_by(discord_id: event.member.id)&.destroy
  end

  def passgen
    Passgen::generate(pronouncable: true, uppercase: false)
  end

  def debug
    binding.irb
  end

  def bot_schedule(event)
    @manager&.bot_schedule(event)
  end
end
