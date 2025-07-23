require 'discordrb'
require 'literal'
require 'tanuki_emoji'
require 'yaml'
require 'active_record'
require 'active_model'
require 'chronic'
require 'rufus-scheduler'

require_relative File.join(Dir.pwd, '..', 'map', 'map.rb')

ActiveRecord::Base.establish_connection(YAML.load_file(File.join(Dir.pwd, '..', 'config', 'database.yml'), aliases: true)[ENV.fetch('BOT_ENV', 'development')])

#include activemodel models for interacting with the database
Dir.glob(File.join(Dir.pwd, '..', 'models', '*.rb')).each do |model|
  require_relative model
end

#include all patches to relevant classes because discordrb is lowk dumb
Dir.glob(File.join(Dir.pwd, '..', 'patches', '*.rb')).each do |patch|
  require_relative patch
end

#load bot information and test server
INFO = DiscordInfo.first
TEST = Server.find_by(name: 'Test')

class Bot
  attr_reader :bot, :map, :scheduler

  def initialize
    @token = INFO.token
    @bot = Discordrb::Commands::CommandBot.new token: @token, prefix: "!", intents: [:server_messages, :server_members], ignore_bots: true
    @bot.init_cache
    @map = Map.new
    @scheduler = Rufus::Scheduler.new
    register_commands
    set_button_handlers
    set_modal_handlers
    set_commands
    at_exit { @bot.stop }
  end

  # @param emoji for sunday school reaction [String]
  # @param emoji for normal service reaction [String]
  # @return message sent [Discordrb::Message]
  def send_sunday_rides(one=TanukiEmoji.find_by_alpha_code(':taxi:').codepoints, two=TanukiEmoji.find_by_alpha_code(':automobile:').codepoints)
    bot.send(TEST.channels.first,
      "@Riders react with #{one} if you would like a ride to sunday school at 9:30 or react with #{two} if you would like to a ride at 10:30!",
    )
  end

  # @param id of rides message [Integer]
  # @return array of users [Array<Discordrb::User>]
  def get_sunday_rides(message_id)
    @bot.channel(TEST.channels.first).load_message(message_id).all_reaction_users
  end

  # @param server id [Integer]
  # @return array of roles [Array<Discordrb::Role>]
  def get_all_roles(server)
    bot.server(server).roles
  end

  # @param server id [Integer]
  # @return array of users [Array<Discordrb::Member>]
  def get_all_users(server)
    bot.server(server).non_bot_members
  end

  def run
    @bot.run
  end

  private
  def register_commands
    bot.register_application_command(:event, 'event commands') do |event_cmd|
      event_cmd.subcommand(:create, 'create a new event')
    end
  end

  def set_commands
    bot.command :user do |event|
      event.user.name
    end

    bot.application_command(:event).subcommand(:create) do |event|
      event_create_message event
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
  end

  def set_button_handlers
    bot.button custom_id: /create_event_button_(\d+)/ do |event|
      id = event.custom_id.match(/create_event_button_(\d+)/)[1].to_i
      event_create_pt_two event, id
    end

    bot.button custom_id: /event_create_modal_1_(\d+)/ do |event|
      id = event.custom_id.match(/event_create_modal_1_(\d+)/)[1].to_i
      event_create_pt_one event, id
    end

    bot.button custom_id: /event_create_modal_2_(\d+)/ do |event|
      id = event.custom_id.match(/event_create_modal_2_(\d+)/)[1].to_i
      event_create_pt_two event, id
    end

    bot.button custom_id: /event_disable_(\d+)/ do |event|
      event.defer_update
      id = event.custom_id.match(/event_disable_(\d+)/)[1].to_i
      event_disable event, id
    end

    bot.button custom_id: /event_delete_(\d+)/ do |event|
      event.defer_update
      id = event.custom_id.match(/event_delete_(\d+)/)[1].to_i
      event_delete event, id
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

    loc = if event.value('location')
      Location.search_by_name(event.value('location')).first
    elsif !loc && event.value('lat') && event.value('lon')
      Location.search_by_coords(event.value('lat'), event.value('lon')).first
    else
      nil
    end

    values = {
      name: event.value('name'),
      location: loc,
      channel: Channel.find_by(name: event.value('channel'))
    }.delete_if{ |_, value| value.nil? || (value.is_a?(String) && value.empty?) }

    evt.update(values)

    _, pt_2_button, disable_button = get_changable_event_create_components event, id

    emoji, style = if !(evt.name && evt.location && evt.channel)
      [ nil, :primary ]
    else
      [ TanukiEmoji.find_by_alpha_code(':ballot_box_with_check:').codepoints, :success ]
    end

    event.update_message content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: emoji&.to_s
        row.button label: 'Pt 2', style: pt_2_button.style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: pt_2_button.emoji&.to_s
        row.button label: disable_button.label, style: disable_button.style, custom_id: "event_disable_#{'%05d' % id}", emoji: disable_button.emoji&.to_s
        row.button label: 'Delete event', style: :danger, custom_id: "event_delete_#{'%05d' % id}"
      end
    end
  end

  # @param event [Discordrb::Events::ModalSubmitEvent]
  # @param id [Integer]
  # @return updated message interaction [Discordrb::Events::InteractionCreateEvent]
  def handle_event_create_pt_two(event, id)
    evt = Event.find(id)

    values = {
      start_time: Chronic.parse(event.value('start_time'))&.to_datetime&.parseable,
      end_time: Chronic.parse(event.value('end_time'))&.to_datetime&.parseable,
      message_rides_at: Chronic.parse(event.value('message_time'))&.to_datetime&.parseable,
      collect_rides_at: Chronic.parse(event.value('collect_time'))&.to_datetime&.parseable,
      repeats_every: event.value('repeat').nil? || event.value('repeat').empty? ? 'never' : event.value('repeat').downcase
    }.delete_if{ |_, value| value.nil? || (value.is_a?(String) && value.empty?) }

    evt.update(values)

    pt_1_button, _, disable_button = get_changable_event_create_components event, id

    emoji, style = if !(evt.start_time && evt.end_time && evt.message_rides_at && evt.collect_rides_at)
      [ nil, :primary ]
    else
      [ TanukiEmoji.find_by_alpha_code(':ballot_box_with_check:').codepoints, :success ]
    end

    event.update_message content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: pt_1_button.style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: pt_1_button.emoji&.to_s
        row.button label: 'Pt 2', style: style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: emoji&.to_s
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
        row.text_input(style: :short, custom_id: 'repeat', label: 'Repeat every (week/month/year/never(blank))', placeholder: evt.repeats_every, required: false)
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

    pt_1_button, pt_2_button, disable_button = get_changable_event_create_components event, id

    emoji, style, label = if disable_button.emoji
      [ nil, :danger, 'Disable event' ]
    else
      [ TanukiEmoji.find_by_alpha_code(':pause_button:').codepoints, :secondary, 'Enable event' ]
    end


    event.edit_response content: event.message.content do |_, view|
      view.row do |row|
        row.button label: 'Pt 1', style: pt_1_button.style, custom_id: "event_create_modal_1_#{'%05d' % id}", emoji: pt_1_button.emoji&.to_s
        row.button label: 'Pt 2', style: pt_2_button.style, custom_id: "event_create_modal_2_#{'%05d' % id}", emoji: pt_2_button.emoji&.to_s
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
  # @return part 1, part , and disable buttons [Array<Discordrb::Components::Button>]
  def get_changable_event_create_components(event, id)
    [
      event.get_component("event_create_modal_1_#{'%05d' % id}"),
      event.get_component("event_create_modal_2_#{'%05d' % id}"),
      event.get_component("event_disable_#{'%05d' % id}")
    ]
  end
end

BOT = Bot.new
BOT.run
