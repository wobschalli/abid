class Messenger < Bot
  attr_reader :bot, :map, :token

  # @param bot token [String]
  def initialize(token)
    @token = token
    @map = Map.new
    @bot = Discordrb::Commands::CommandBot.new token: @token, prefix: "!", intents: [:server_messages, :server_members], ignore_bots: true
    @bot.init_cache
    register_commands
    set_button_handlers
    set_modal_handlers
    set_commands
    set_event_handlers
    at_exit do
      @bot.stop
    end
  end

  # @param message [String]
  # @return message sent [Discordrb::Message]
  def dm_ian(message) #mostly for testing purposes, but also just for the trolls
    @bot.user(User.find_by(name: 'ian').discord_id).dm(message)
  end

  # @param message [String]
  # @return message sent [Discordrb::Message]
  def dm_alan(message) #mostly for testing purposes, but also just for the trolls
    @bot.user(User.find_by(name: 'alan').discord_id).dm(message)
  end

  # @param server id [Integer]
  # @return array of roles [Array<Discordrb::Role>]
  def get_all_roles(server)
    @bot.server(server).roles
  end

  # @param background [true, false]
  def run(background=true)
    @bot.run(background)
    true
  end

  # @param channel id [Discordrb::Channel, String, Integer]
  # @param message [String]
  # @param tts [true, false]
  # @param embeds [Hash, Discordrb::Webhooks::Embed, Array<Hash>, Array<Discordrb::Webhooks::Embed> nil]
  # @param attachments [Array<File>]
  # @param allowed_mentions [Hash, Discordrb::AllowedMentions, false, nil]
  # @param message_reference [Hash, Discordrb::AllowedMentions, false, nil]
  # @param components [View, Array<Hash>]
  # @param timeout [Float, nil]
  # @returns [Discordrb::Message]
  def send(channel, message, tts:false, embeds:nil, attachments:nil, allowed_mentions:false, message_reference:nil, components:nil, timeout:nil)
    @bot.send(channel, message, tts: tts, embeds: embeds, attachments: attachments, allowed_mentions: allowed_mentions, message_reference: message_reference, components: components, timeout: timeout)
  end

  private
  def register_commands
    bot.register_application_command(:event, 'event commands') do |event_cmd|
      event_cmd.subcommand(:create, 'create a new event')
    end

    bot.register_application_command(:login, 'send a login code', server_id: Server.find_by(name: 'Abide').discord_id)
  end

  def set_commands
    bot.command :user do |event|
      event.user.name
    end

    bot.application_command(:event).subcommand(:create) do |event|
      return event.respond('You are not allowed to do that!') unless User.find_by(discord_id: event.user.id).leader
      event_create_message event
    end

    bot.application_command(:login) do |event|
      user = User.find_by(discord_id: event.user.id)
      return event.respond('You are not able to do that!', ephemeral: true) unless user.leader
      handle_login_code(user)
      event.respond content: 'Your login code has been sent', ephemeral: true
    end

    bot.application_command(:debug) do |event|
      if User.find_by(discord_id: event.user.id)&.leader
        event.defer
        debug
        event.send_message(content: 'Your debug session is finished', ephemeral: true)
      else
        dm_ian("an unauthorized user (#{event.user.username} | #{event.user.id}) attempted to use debug")
        event.respond 'You do not have the proper authentication to perform this action!'
      end
    end
  end

  def set_modal_handlers
    bot.modal_submit custom_id: /create_event_modal_1_(\d+)/ do |event|
      id = event.custom_id.match(/create_event_modal_1_(\d+)/)[1].to_i
      handle_event_create_pt_one event, id
    end

    bot.modal_submit custom_id: /create_event_modal_2_(\d+)/ do |event|
      id = event.custom_id.match(/create_event_modal_2_(\d+)/)[1].to_i
      handle_event_create_pt_two event, id
    end

    bot.modal_submit custom_id: /create_event_modal_3_(\d+)/ do |event|
      id = event.custom_id.match(/create_event_modal_3_(\d+)/)[1].to_i
      handle_event_create_pt_three event, id
    end
  end

  def set_button_handlers
    bot.button custom_id: /event_create_modal_1_(\d+)/ do |event|
      return event.respond('You don\'t have permission to do this!') unless User.find_by(discord_id: event.user.id).leader
      id = event.custom_id.match(/event_create_modal_1_(\d+)/)[1].to_i
      event_create_pt_one event, id
    end

    bot.button custom_id: /event_create_modal_2_(\d+)/ do |event|
      return event.respond('You don\'t have permission to do this!') unless User.find_by(discord_id: event.user.id).leader
      id = event.custom_id.match(/event_create_modal_2_(\d+)/)[1].to_i
      event_create_pt_two event, id
    end

    bot.button custom_id: /event_create_modal_3_(\d+)/ do |event|
      return event.respond('You don\'t have permission to do this!') unless User.find_by(discord_id: event.user.id).leader
      id = event.custom_id.match(/event_create_modal_3_(\d+)/)[1].to_i
      event_create_pt_three event, id
    end

    bot.button custom_id: /event_disable_(\d+)/ do |event|
      return event.respond('You don\'t have permission to do this!') unless User.find_by(discord_id: event.user.id).leader
      event.defer_update
      id = event.custom_id.match(/event_disable_(\d+)/)[1].to_i
      event_disable event, id
    end

    bot.button custom_id: /event_delete_(\d+)/ do |event|
      return event.respond('You don\'t have permission to do this!') unless User.find_by(discord_id: event.user.id).leader
      event.defer_update
      id = event.custom_id.match(/event_delete_(\d+)/)[1].to_i
      event_delete event, id
    end
  end

  def set_event_handlers
    @bot.member_join do |event|
      handle_member_join event
    end

    @bot.member_leave do |event|
      handle_member_leave event
    end
  end

  # @param event [Discordrb::Events::ButtonEvent]
  # @param id [Integer]
  # @return event creation part one modal [Discordrb::Webhooks::Modal]
  def event_create_pt_one(event, id)
    evt = Event.find id
    loc = evt.location

    event.show_modal(title: 'Part 1', custom_id: "create_event_modal_1_#{'%05d' % id}") do |modal|
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'name', label: 'Name', placeholder: evt.name, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'location', label: 'Location', placeholder: (loc&.name), required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'lat', label: 'Latitude', placeholder: loc&.lat&.to_s, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'lon', label: 'Longitude', placeholder: loc&.lon&.to_s, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'channel', label: 'Channel Name', placeholder: evt.channel&.name, required: false)
      end
    end
  end

  # @param event [Discordrb::Events::ModalSubmitEvent]
  # @param id [Integer]
  # @return updated message interaction [Discordrb::Events::InteractionCreateEvent]
  def handle_event_create_pt_one(event, id)
    evt = Event.find(id)

    loc = if event.value('location') #God, please forgive me for this block
      Location.search_by_name(event.value('location')).first
    elsif event.value('lat') && event.value('lon')
      Location.search_by_coords(event.value('lat'), event.value('lon')).first
    end || @map.create_new_location(event.value('location') || { lat: event.value('lat'), lon: event.value('lon') }) || evt.location

    values = {
      name: event.value('name') || evt.name,
      location: loc,
      channel: Channel.find_by(name: event.value('channel')) || evt.channel
    }.delete_if{ |_, value| value.nil? || (value.is_a?(String) && value.empty?) }

    evt.update(values)

    _, pt_2_button, pt_3_button, disable_button = get_changable_event_create_components event, id

    emoji, style = if !(evt.name && evt.location && evt.channel)
      [ nil, :primary ]
    else
      [ TanukiEmoji.find_by_alpha_code(':ballot_box_with_check:').codepoints, :success ]
    end

    event.update_message content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: emoji&.to_s
        row.button label: 'Pt 2', style: pt_2_button.style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: pt_2_button.emoji&.to_s
        row.button label: 'Pt 3', style: pt_3_button.style, custom_id: "event_create_modal_3_#{'%05d' % id}", emoji: pt_3_button.emoji&.to_s
        row.button label: disable_button.label, style: disable_button.style, custom_id: "event_disable_#{'%05d' % id}", emoji: disable_button.emoji&.to_s
        row.button label: 'Delete event', style: :danger, custom_id: "event_delete_#{'%05d' % id}"
      end
    end
  end

  # @param event [Discordrb::Events::ButtonEvent]
  # @param id [Integer]
  # @return event creation part two modal [Discordrb::Webhooks::Modal]
  def event_create_pt_two(event, id)
    evt = Event.find(id)
    event.show_modal(title: 'Part 2', custom_id: "create_event_modal_2_#{'%05d' % evt.id}") do |modal|
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'start_time', label: 'Start Time', placeholder: evt.start_time, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'end_time', label: 'End Time', placeholder: evt.end_time, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'message_time', label: 'Message Time', placeholder: evt.message_rides_at, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'collect_time', label: 'Collect Time', placeholder: evt.collect_rides_at, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'repeat', label: 'Repeat every (week/never(blank))', placeholder: evt.repeats_every, required: false)
      end
    end
  end

  # @param event [Discordrb::Events::ModalSubmitEvent]
  # @param id [Integer]
  # @return updated message interaction [Discordrb::Events::InteractionCreateEvent]
  def handle_event_create_pt_two(event, id)
    evt = Event.find(id)

    values = {
      start_time: Chronic.parse(event.value('start_time')) || evt.start_time,
      end_time: Chronic.parse(event.value('end_time')) || evt.end_time,
      message_rides_at: Chronic.parse(event.value('message_time')) || evt.message_rides_at,
      collect_rides_at: Chronic.parse(event.value('collect_time')) || evt.collect_rides_at,
      repeats_every: event.value('repeat').nil? || (event.value('repeat').empty? ? 'never' : event.value('repeat').downcase) || evt.repeats_every
    }.delete_if{ |_, value| value.nil? || (value.is_a?(String) && value.empty?) }

    evt.update(values)

    pt_1_button, _, pt_3_button, disable_button = get_changable_event_create_components event, id

    emoji, style = if !(evt.start_time && evt.end_time && evt.message_rides_at && evt.collect_rides_at)
      [ nil, :primary ]
    else
      [ TanukiEmoji.find_by_alpha_code(':ballot_box_with_check:').codepoints, :success ]
    end

    bot_schedule(evt) if evt.schedulable?

    event.update_message content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: pt_1_button.style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: pt_1_button.emoji&.to_s
        row.button label: 'Pt 2', style: style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: emoji&.to_s
        row.button label: 'Pt 3', style: pt_3_button.style, custom_id: "event_create_modal_3_#{'%05d' % id}", emoji: pt_3_button.emoji&.to_s
        row.button label: disable_button.label, style: disable_button.style, custom_id: "event_disable_#{'%05d' % id}", emoji: disable_button.emoji&.to_s
        row.button label: 'Delete event', style: :danger, custom_id: "event_delete_#{'%05d' % id}"
      end
    end
  end

  # @param event [Discordrb::Events::ButtonEvent]
  # @param id [Integer]
  # @return event creation part two modal [Discordrb::Webhooks::Modal]
  def event_create_pt_three(event, id)
    evt = Event.find(id)
    event.show_modal(title: 'Part 3', custom_id: "create_event_modal_3_#{'%05d' % evt.id}") do |modal|
      modal.row do |row|
        row.text_input(style: :paragraph, custom_id: 'message', label: 'Message', placeholder: evt.message, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'reaction_1', label: 'Reaction 1 (name/character/blank)', placeholder: evt.emojis&.first&.modal_display, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'reaction_2', label: 'Reaction 2 (name/character/blank)', placeholder: evt.emojis&.second&.modal_display, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'reaction_3', label: 'Reaction 3 (name/character/blank)', placeholder: evt.emojis&.third&.modal_display, required: false)
      end
      modal.row do |row|
        row.text_input(style: :short, custom_id: 'reaction_4', label: 'Reaction 4 (name/character/blank)', placeholder: evt.emojis&.fourth&.modal_display, required: false)
      end
    end
  end

  # @param event [Discordrb::Events::ModalSubmitEvent]
  # @param id [Integer]
  # @return updated message interaction [Discordrb::Events::InteractionCreateEvent]
  def handle_event_create_pt_three(event, id)
    evt = Event.find(id)

    emojis = 1.upto(4).map do |x| #using i is for your normal cs major
      response = event.value("reaction_#{x}")
      if t_emoji = TanukiEmoji.find_by_codepoints(response)
        Emoji.find_or_create_by(name: t_emoji.name)
      elsif t_emoji = TanukiEmoji.find_by_alpha_code(":#{response.remove(':')}:")
        Emoji.find_or_create_by(name: t_emoji.name)
      elsif emoji = Emoji.find_by(name: response)
        emoji
      elsif emoji = Emoji.find_by(discord_id: response.to_i)
        emoji
      else
        nil
      end
    end.delete_if{ |value| value.nil? } || evt.emojis

    values = {
      message: event.value('message') || evt.message,
      emojis: emojis
    }.delete_if{ |_, value| value.nil? || (value.is_a?(String) && value.empty?) || (value.is_a?(Array) && value.empty?) }

    evt.update(values)

    pt_1_button, pt_2_button, _, disable_button = get_changable_event_create_components event, id

    emoji, style = if !(evt.message && evt.emojis.length > 0)
      [ nil, :primary ]
    else
      [ TanukiEmoji.find_by_alpha_code(':ballot_box_with_check:').codepoints, :success ]
    end

    bot_schedule(evt) if evt.schedulable?

    event.update_message content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: pt_1_button.style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: pt_1_button.emoji&.to_s
        row.button label: 'Pt 2', style: pt_2_button.style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: pt_2_button.emoji&.to_s
        row.button label: 'Pt 3', style: style, custom_id: "event_create_modal_3_#{'%05d' % id}", emoji: emoji&.to_s
        row.button label: disable_button.label, style: disable_button.style, custom_id: "event_disable_#{'%05d' % id}", emoji: disable_button.emoji&.to_s
        row.button label: 'Delete event', style: :danger, custom_id: "event_delete_#{'%05d' % id}"
      end
    end
  end

  # @param event [Discordrb::Events::SubcommandBuilder]
  # @param id [Integer]
  # @return event creation part one modal [Discordrb::Webhooks::Modal]
  def event_create_message(event)
    evt = Event.create
    event.respond content: "Please fill out the following modals to create the event. All previously entered information will be shown in the text placeholders" do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: :primary, custom_id: "event_create_modal_1_#{'%05d' % evt.id}"
        row.button label: 'Pt 2', style: :primary, custom_id: "event_create_modal_2_#{'%05d' % evt.id}"
        row.button label: 'Pt 3', style: :primary, custom_id: "event_create_modal_3_#{'%05d' % evt.id}"
        row.button label: 'Disable event', style: :danger, custom_id: "event_disable_#{'%05d' % evt.id}"
        row.button label: 'Delete event', style: :danger, custom_id: "event_delete_#{'%05d' % evt.id}"
      end
    end
  end

  # @param event [Discordrb::Events::ButtonEvent]
  # @param id [Integer]
  # @return edit message to say event is disabled [Discordrb::Events::InteractionCreateEvent]
  def event_disable(event, id)
    evt = Event.find(id)
    evt.update(disabled: !evt.disabled)

    pt_1_button, pt_2_button, pt_3_button, disable_button = get_changable_event_create_components event, id

    emoji, style, label = if disable_button.emoji
      [ nil, :danger, 'Disable event' ]
    else
      [ TanukiEmoji.find_by_alpha_code(':pause_button:').codepoints, :secondary, 'Enable event' ]
    end


    event.edit_response content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: pt_1_button.style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: pt_1_button.emoji&.to_s
        row.button label: 'Pt 2', style: pt_2_button.style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: pt_2_button.emoji&.to_s
        row.button label: 'Pt 3', style: pt_3_button.style, custom_id: "event_create_modal_3_#{'%05d' % id}", emoji: pt_3_button.emoji&.to_s
        row.button label: label, style: style, custom_id: "event_disable_#{'%05d' % id}", emoji: emoji&.to_s
        row.button label: 'Delete event', style: :danger, custom_id: "event_delete_#{'%05d' % id}"
      end
    end
  end

  # @param event [Discordrb::Events::ButtonEvent]
  # @param id [Integer]
  # @return delete message for event [Discordrb::Events::InteractionCreateEvent]
  def event_delete(event, id)
    evt = Event.find(id)
    evt.destroy

    event.delete_response
  end

  # @param event [Discordrb::Events::ModalSubmitEvent]
  # @param id [Integer]
  # @return part 1, part 2, part3, and disable buttons [Array<Discordrb::Components::Button>]
  def get_changable_event_create_components(event, id)
    [
      event.get_component("event_create_modal_1_#{'%05d' % id}"),
      event.get_component("event_create_modal_2_#{'%05d' % id}"),
      event.get_component("event_create_modal_3_#{'%05d' % id}"),
      event.get_component("event_disable_#{'%05d' % id}")
    ]
  end

  # @param user [User]
  def handle_login_code(user)
    code = passgen
    user.update(password: code, password_confirmation: code)
    @bot.user(user.discord_id).dm("Here is your login code: #{code}")
  end

  # @param event [Discordrb::Events::ServerMemberAddEvent]
  def handle_member_join(event)
    return unless Server.find_by(name: 'Abide').discord_id == event.server.id #we only care if it's the abide server
    User.find_or_create_by(discord_id: event.member.id) do |user|
      pass = passgen
      user.username = event.member.username
      user.name = event.member.display_name
      user.leader = event.member.permission?(:administrator) || event.member.role?('Leaders') || event.member.role?('Coordinator')
      user.password = pass
      user.password_confirmation = pass
    end
  end

  # @param event [Discordrb::Events::ServerMemberDeleteEvent]
  def handle_member_leave(event)
    return unless Server.find_by(name: 'Abide').discord_id == event.server.id
    User.find_by(discord_id: event.member.id).destroy
  end
end

# i[' ]?a?m (.+)
