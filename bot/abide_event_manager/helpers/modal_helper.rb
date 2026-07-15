module ModalHelper

  private

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
               else
                 # nothing
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

    if (t_emoji = TanukiEmoji.find_by_codepoints(cleaned))
      Emoji.find_or_create_by(name: t_emoji.name) do |e|
        e.server = server if server
      end
    elsif (t_emoji = TanukiEmoji.find_by_alpha_code(":#{cleaned}:"))
      Emoji.find_or_create_by(name: t_emoji.name) do |e|
        e.server = server if server
      end
    elsif (emoji = Emoji.find_by(name: cleaned))
      emoji
    elsif (emoji = Emoji.find_by(discord_id: cleaned.to_i))
      emoji
    else
      nil
    end
  end
end
