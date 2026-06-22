require_relative 'event_draft'

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
    @client.user(User.find_by(name: 'ian').discord_id).dm(message)
  end

  def dm_alan(message)
    @client.user(User.find_by(name: 'alan').discord_id).dm(message)
  end

  def dm_bfm(message)
    @client.user(User.find_by(name: 'bfm').discord_id).dm(message)
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
      return event.respond(content: 'You are not able to do that!', ephemeral: true) unless user.leader
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
  # Permission / draft helpers
  # ---------------------------------------------------------------------------

  def with_draft(event)
    draft_id = event.custom_id.to_s.split('_').last
    draft = EventDraft.find(draft_id)
    return event.respond(content: 'This draft has expired or was already saved.', ephemeral: true) unless draft

    user = User.find_by(discord_id: event.user.id)
    return event.respond(content: 'You don\'t have permission to do this!', ephemeral: true) unless user&.leader || user&.coordinator? || draft.organizer_id == user&.id

    yield draft
  end

  def with_event(event)
    event_id = event.custom_id.to_s.match(/_(\d+)$/)&.[](1).to_i
    evt = Event.find_by(id: event_id)
    return event.respond(content: 'Event not found.', ephemeral: true) unless evt

    user = User.find_by(discord_id: event.user.id)
    return event.respond(content: 'You don\'t have permission to do this!', ephemeral: true) unless user&.leader || user&.coordinator? || evt.organizer_id == user&.id

    yield evt
  end

  def with_draft_or_event(event)
    identifier = event.custom_id.to_s.split('_').last
    if identifier.to_s.match?(/\A[0-9a-f]{8}\z/i)
      with_draft(event) { |draft| yield draft }
    else
      with_event(event) do |evt|
        draft = EventDraft.for_event(evt, organizer_id: evt.organizer_id)
        yield draft
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Dashboard rendering
  # ---------------------------------------------------------------------------

  def event_dashboard_embed(obj)
    if obj.is_a?(EventDraft)
      draft_dashboard_embed(obj)
    else
      persisted_event_dashboard_embed(obj)
    end
  end

  def draft_dashboard_embed(draft)
    {
      title: "🛠️ Event Builder: #{draft.name || 'Untitled'}",
      description: "Use the buttons below to configure your event. All changes are saved to this message until you publish.",
      color: 0x3498db,
      fields: [
        { name: '📝 Basics', value: basics_field_value(draft) },
        { name: '🕒 Timing', value: timing_field_value(draft) },
        { name: '🎭 Reactions', value: reactions_field_value(draft) },
        { name: '📊 Status', value: "In-progress draft" }
      ]
    }
  end

  def persisted_event_dashboard_embed(evt)
    {
      title: "📅 Event: #{evt.name || 'Untitled'}",
      description: "Use the buttons below to manage this event.",
      color: event_color(evt),
      fields: [
        { name: '📝 Basics', value: basics_field_value(evt) },
        { name: '🕒 Timing', value: timing_field_value(evt) },
        { name: '🎭 Reactions', value: reactions_field_value(evt) },
        { name: '📊 Status', value: evt.status.to_s.capitalize }
      ]
    }
  end

  def event_color(evt)
    case evt.status
    when 'unpublished' then 0x95a5a6
    when 'scheduled' then 0x3498db
    when 'active' then 0x2ecc71
    when 'completed' then 0x9b59b6
    when 'cancelled' then 0xe74c3c
    else 0x3498db
    end
  end

  def basics_field_value(obj)
    loc = obj.location
    chan = obj.channel
    <<~VALUE.strip
      **Name:** #{obj.name || 'Not set'}
      **Location:** #{loc ? "#{loc.name} (#{loc.lat}, #{loc.lon})" : 'Not set'}
      **Channel:** #{chan&.name || 'Not set'}
    VALUE
  end

  def timing_field_value(obj)
    <<~VALUE.strip
      **Start:** #{format_time(obj.start_time)}
      **End:** #{format_time(obj.end_time)}
      **Message At:** #{format_time(obj.message_rides_at)}
      **Collect At:** #{format_time(obj.collect_rides_at)}
      **Repeats:** #{obj.repeats_every || 'never'}
    VALUE
  end

  def reactions_field_value(obj)
    emojis = obj.respond_to?(:emojis) ? obj.emojis.to_a : (obj.emojis || [])
    emoji_text = emojis.any? ? emojis.map(&:modal_display).join(', ') : 'None'
    <<~VALUE.strip
      **Message:** #{obj.message || 'Not set'}
      **Emojis:** #{emoji_text}
    VALUE
  end

  def format_time(time)
    return 'Not set' unless time
    "<t:#{time.to_i}:F>"
  end

  def render_builder_components(view, draft)
    view.row do |row|
      row.button label: '📝 Edit Basics', style: section_style(draft, :basics), custom_id: "event_edit_basics_#{draft.id}"
      row.button label: '🕒 Edit Timing', style: section_style(draft, :timing), custom_id: "event_edit_timing_#{draft.id}"
      row.button label: '🎭 Edit Reactions', style: section_style(draft, :reactions), custom_id: "event_edit_reactions_#{draft.id}"
    end

    view.row do |row|
      row.channel_select(
        custom_id: "event_set_channel_#{draft.id}",
        placeholder: draft.channel ? "Channel: #{draft.channel.name}" : 'Select a channel',
        min_values: 1,
        max_values: 1
      )
    end

    view.row do |row|
      if draft.ready_to_publish?
        row.button label: '🚀 Publish', style: :success, custom_id: "event_publish_#{draft.id}"
      else
        row.button label: '🚀 Publish (Needs Info)', style: :secondary, custom_id: "event_publish_disabled_#{draft.id}", disabled: true
      end

      if draft.ready_to_save?
        row.button label: '💾 Save as Unpublished', style: :primary, custom_id: "event_save_unpublished_#{draft.id}"
      else
        row.button label: '💾 Save as Unpublished', style: :secondary, custom_id: "event_save_unpublished_disabled_#{draft.id}", disabled: true
      end

      row.button label: '❌ Discard', style: :danger, custom_id: "event_discard_#{draft.id}"
    end
  end

  def render_event_management_components(view, evt)
    view.row do |row|
      row.button label: '📝 Edit Basics', style: section_style(evt, :basics), custom_id: "event_edit_basics_#{evt.id}"
      row.button label: '🕒 Edit Timing', style: section_style(evt, :timing), custom_id: "event_edit_timing_#{evt.id}"
      row.button label: '🎭 Edit Reactions', style: section_style(evt, :reactions), custom_id: "event_edit_reactions_#{evt.id}"
      row.button label: '📄 Duplicate', style: :primary, custom_id: "event_duplicate_#{evt.id}"
    end

    view.row do |row|
      if evt.unpublished?
        row.button label: '▶️ Republish', style: :success, custom_id: "event_republish_#{evt.id}"
        row.button label: '🗑️ Delete', style: :danger, custom_id: "event_delete_#{evt.id}"
      elsif evt.scheduled? || evt.active?
        row.button label: '⏸️ Unpublish', style: :secondary, custom_id: "event_unpublish_#{evt.id}"
        row.button label: '🚫 Cancel Event', style: :danger, custom_id: "event_cancel_#{evt.id}"
      else
        row.button label: '🗑️ Delete', style: :danger, custom_id: "event_delete_#{evt.id}"
      end
    end
  end

  def section_style(obj, section)
    complete = case section
               when :basics then obj.name && obj.location && obj.channel
               when :timing then obj.start_time && obj.end_time && obj.message_rides_at && obj.collect_rides_at
               when :reactions then obj.message && obj.emojis.to_a.any?
               end
    complete ? :success : :primary
  end

  def refresh_dashboard(event, draft)
    event.update_message(content: '', embeds: [event_dashboard_embed(draft)]) do |_, view|
      render_builder_components(view, draft)
    end
  end

  # ---------------------------------------------------------------------------
  # Modals
  # ---------------------------------------------------------------------------

  def show_edit_basics_modal(event, draft)
    loc = draft.location
    event.show_modal(title: '📝 Edit Basics', custom_id: "event_modal_basics_#{draft.id}") do |modal|
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'name', label: 'Name', placeholder: draft.name, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'location', label: 'Location (address or place name)', placeholder: loc&.name, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'lat', label: 'Latitude (optional)', placeholder: loc&.lat&.to_s, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'lon', label: 'Longitude (optional)', placeholder: loc&.lon&.to_s, required: false)
      end
    end
  end

  def show_edit_timing_modal(event, draft)
    event.show_modal(title: '🕒 Edit Timing', custom_id: "event_modal_timing_#{draft.id}") do |modal|
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'start_time', label: 'Start Time', placeholder: draft.start_time&.strftime('%Y-%m-%d %H:%M') || 'e.g. Friday at 6pm', required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'end_time', label: 'End Time', placeholder: draft.end_time&.strftime('%Y-%m-%d %H:%M') || 'e.g. Friday at 9pm', required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'message_time', label: 'Message Time', placeholder: draft.message_rides_at&.strftime('%Y-%m-%d %H:%M') || 'e.g. Thursday at 6pm', required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'collect_time', label: 'Collect Time', placeholder: draft.collect_rides_at&.strftime('%Y-%m-%d %H:%M') || 'e.g. Friday at 8am', required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'repeat', label: 'Repeat every (week/never)', placeholder: draft.repeats_every || 'never', required: false)
      end
    end
  end

  def show_edit_reactions_modal(event, draft)
    emojis = draft.emojis.to_a
    event.show_modal(title: '🎭 Edit Reactions', custom_id: "event_modal_reactions_#{draft.id}") do |modal|
      modal.row do |row|
        row.text_input(style: :paragraph, custom_id: 'message', label: 'Message', placeholder: draft.message, required: false)
      end
      4.times do |i|
        modal.row do |row|
          row.text_input(style: :short, custom_id: "reaction_#{i + 1}", label: "Reaction #{i + 1}", placeholder: emojis[i]&.modal_display, required: false)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Modal handlers
  # ---------------------------------------------------------------------------

  def handle_edit_basics(event, draft)
    name = event.value('name')
    draft.name = name if name && !name.strip.empty?

    location_input = event.value('location')
    lat_input = event.value('lat')
    lon_input = event.value('lon')

    loc = nil
    if location_input && !location_input.strip.empty?
      loc = Location.search_by_name(location_input).first || @map.create_new_location(location_input)
    elsif lat_input && lon_input && !lat_input.strip.empty? && !lon_input.strip.empty?
      loc = Location.search_by_coords(lat_input, lon_input).first || @map.create_new_location({ lat: lat_input, lon: lon_input })
    end

    if loc
      draft.location = loc
    elsif location_input || lat_input || lon_input
      return event.respond(content: 'Could not resolve that location. Try a more specific address or leave coordinates blank.', ephemeral: true)
    end

    refresh_dashboard(event, draft)
  end

  def handle_edit_timing(event, draft)
    parsed = {}
    errors = []

    { start_time: 'start_time', end_time: 'end_time', message_rides_at: 'message_time', collect_rides_at: 'collect_time' }.each do |attr, input_id|
      value = event.value(input_id)
      next unless value && !value.strip.empty?
      parsed_time = parse_time(value)
      if parsed_time
        parsed[attr] = parsed_time
      else
        errors << "Could not understand #{input_id.humanize}."
      end
    end

    return event.respond(content: errors.join("\n"), ephemeral: true) if errors.any?

    parsed.each { |attr, time| draft.send("#{attr}=", time) }

    repeat = event.value('repeat')
    draft.repeats_every = if repeat.nil? || repeat.strip.empty?
                            draft.repeats_every || 'never'
                          else
                            repeat.strip.downcase
                          end

    time_errors = draft.validation_errors
    if time_errors.any?
      return event.respond(content: "Times updated, but they don't look right yet:\n#{time_errors.join("\n")}", ephemeral: true)
    end

    refresh_dashboard(event, draft)
  end

  def handle_edit_reactions(event, draft)
    message = event.value('message')
    draft.message = message if message && !message.strip.empty?

    server = draft.channel&.server
    emojis = 1.upto(4).map do |x|
      response = event.value("reaction_#{x}")
      next nil unless response && !response.strip.empty?
      resolve_emoji(response, server: server)
    end.compact

    draft.emojis = emojis if emojis.any?

    refresh_dashboard(event, draft)
  end

  def parse_time(value)
    parsed = Chronic.parse(value)
    return nil unless parsed

    # Ensure the parsed time is expressed in the configured application timezone.
    parsed.respond_to?(:in_time_zone) ? parsed.in_time_zone : Time.zone.parse(parsed.to_s)
  rescue ArgumentError
    nil
  end

  def resolve_emoji(response, server: nil)
    cleaned = response.to_s.strip.delete(':')
    return nil if cleaned.empty?

    if t_emoji = TanukiEmoji.find_by_codepoints(cleaned)
      Emoji.find_or_create_by(name: t_emoji.name) do |e|
        e.server = server if server
      end
    elsif t_emoji = TanukiEmoji.find_by_alpha_code(":#{cleaned}:")
      Emoji.find_or_create_by(name: t_emoji.name) do |e|
        e.server = server if server
      end
    elsif emoji = Emoji.find_by(name: cleaned)
      emoji
    elsif emoji = Emoji.find_by(discord_id: cleaned.to_i)
      emoji
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Publish / save / discard
  # ---------------------------------------------------------------------------

  def publish_draft(event, draft)
    unless draft.ready_to_publish?
      return event.respond(content: 'This event is missing required information before it can be published.', ephemeral: true)
    end

    time_errors = draft.validation_errors
    return event.respond(content: "Cannot publish:\n#{time_errors.join("\n")}", ephemeral: true) if time_errors.any?

    event.defer_update
    evt = persist_draft(draft, status: :scheduled)
    bot_schedule(evt)
    EventDraft.delete(draft.id)

    event.edit_response content: "🚀 Event **#{evt.name}** published and scheduled!", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def save_draft_as_unpublished(event, draft)
    unless draft.ready_to_save?
      return event.respond(content: 'An event name is required to save.', ephemeral: true)
    end

    event.defer_update
    evt = persist_draft(draft, status: :unpublished)
    EventDraft.delete(draft.id)

    event.edit_response content: "💾 Event **#{evt.name}** saved as unpublished.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def discard_draft(event, draft)
    EventDraft.delete(draft.id)
    event.update_message(content: '❌ Draft discarded.', embeds: [], components: [])
  end

  def persist_draft(draft, status:)
    if draft.persisted?
      evt = Event.find(draft.event_id)
      evt.update!(draft.to_event_attributes.merge(status: status, scheduled: (status == :scheduled)))
      evt.emojis = draft.emojis if draft.emojis.any?
      evt
    else
      attrs = draft.to_event_attributes.merge(status: status, scheduled: (status == :scheduled))
      evt = Event.create!(attrs)
      evt.emojis = draft.emojis if draft.emojis.any?
      evt
    end
  end

  # ---------------------------------------------------------------------------
  # Existing event management
  # ---------------------------------------------------------------------------

  def unpublish_event(event, evt)
    event.defer_update
    evt.update!(status: :unpublished)
    evt.unschedule
    event.edit_response content: "⏸️ Event **#{evt.name}** unpublished.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def republish_event(event, evt)
    unless evt.schedulable?
      return event.respond(content: 'Cannot republish: the event is missing required information.', ephemeral: true)
    end

    event.defer_update
    evt.update!(status: :scheduled)
    bot_schedule(evt)
    event.edit_response content: "▶️ Event **#{evt.name}** republished and scheduled.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def cancel_event(event, evt)
    event.defer_update
    evt.update!(status: :cancelled)
    evt.unschedule
    event.edit_response content: "🚫 Event **#{evt.name}** has been cancelled.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def delete_event(event, evt)
    unless evt.unpublished?
      return event.respond(content: 'Only unpublished events can be permanently deleted.', ephemeral: true)
    end

    event.defer_update
    name = evt.name || "Untitled_#{evt.id}"
    evt.destroy
    event.edit_response content: "🗑️ Event **#{name}** has been permanently deleted.", embeds: [], components: []
  end

  def duplicate_event(event, evt)
    user = User.find_by(discord_id: event.user.id)
    return event.respond(content: 'Could not identify your user record.', ephemeral: true) unless user

    draft = EventDraft.create(
      organizer_id: user.id,
      name: generate_duplicate_name(evt.name),
      location: evt.location,
      channel: evt.channel,
      message: evt.message,
      emojis: evt.emojis.to_a,
      start_time: nil,
      end_time: nil,
      message_rides_at: nil,
      collect_rides_at: nil,
      repeats_every: evt.repeats_every
    )

    event.respond content: "📄 Created a template from **#{evt.name}**. Set new times and publish when ready.", embeds: [event_dashboard_embed(draft)] do |_, view|
      render_builder_components(view, draft)
    end
  end

  # ---------------------------------------------------------------------------
  # Naming helpers
  # ---------------------------------------------------------------------------

  def generate_unique_event_name(base_name)
    base = base_name.strip
    existing = Event.where("name LIKE ?", "#{base}%").pluck(:name)
    return base if existing.none?

    numbers = existing.map { |n| n.match(/\((\d+)\)$/)&.[](1).to_i }
    next_number = (numbers.max || 0) + 1
    "#{base} (#{next_number})"
  end

  def generate_duplicate_name(base_name)
    clean_name = base_name.to_s.sub(/\s*\(\d+\)$/, '').strip
    existing = Event.where("name LIKE ?", "#{clean_name}%").pluck(:name)
    return clean_name if existing.none?

    numbers = existing.map { |n| n.match(/\((\d+)\)$/)&.[](1).to_i }
    next_number = (numbers.max || 0) + 1
    "#{clean_name} (#{next_number})"
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
    return unless Server.find_by(name: 'Abide').discord_id == event.server.id

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
