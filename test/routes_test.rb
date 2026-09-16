require_relative 'test_helper'
require 'rack/test'
Abid.load_views
require_relative '../app'

# Registering sinatra-activerecord attaches a stdout logger, which buries the
# test output under every SELECT the views run.
ActiveRecord::Base.logger = nil

# Until now nothing exercised a single route or rendered a single view, so any
# of these pages could 500 and only a human clicking would find out. Phlex
# errors in particular are a runtime surprise: a method name that collides with
# an HTML element, or a nil where a view expects a record, raises only when that
# branch actually renders.
class RoutesTest < AbidTest
  include Rack::Test::Methods

  def app = App

  def setup
    super
    # Rack::Test drives the app in this process, so it shares the transaction
    # this test opened and everything rolls back afterwards.
    App.set :sessions, false
    App.set :show_exceptions, false
    App.set :raise_errors, true
    # Sinatra 4 rejects requests whose Host is not permitted; Rack::Test sends
    # "example.org", which otherwise 403s every request here.
    App.set :host_authorization, { permitted_hosts: [] }

    @leader = User.create!(name: 'Coordinator', username: 'coord', discord_id: next_discord_id,
                           leader: true, password: 'test-password')
    @event = make_event(name: 'Sunday Service')
  end

  # The session is stubbed rather than driven through POST /login, so these
  # tests stay about routing and rendering rather than re-testing auth.
  def as_leader
    env 'rack.session', { user_id: @leader.id }
  end

  def get_ok(path)
    as_leader
    get path
    assert last_response.ok?, "GET #{path} returned #{last_response.status}\n#{last_response.body.to_s[0, 600]}"
    last_response
  end

  def test_every_listing_page_renders
    %w[/ /board /events /series /signups /locations /users].each { |path| get_ok(path) }
  end

  def test_every_record_page_renders
    series = EventSeries.create!(name: 'Friday Bible Study', weekday: 5,
                                 start_time_of_day: '18:30', location: @event.location)
    post = SignupPost.create!(channel: channel, service_date: Time.zone.today, status: 'draft')

    get_ok("/events/#{@event.id}")
    get_ok("/events/#{@event.id}/edit")
    get_ok('/events/new')
    get_ok("/series/#{series.id}")
    get_ok("/series/#{series.id}/edit")
    get_ok('/series/new')
    get_ok("/signups/#{post.id}")
    get_ok("/users/#{@leader.id}")
    get_ok("/events/#{@event.id}/dispatches")
  end

  def test_csv_exports_render
    assert_equal 'text/csv', get_ok("/events/#{@event.id}.csv").content_type.split(';').first
    get_ok("/board/#{@event.id}.csv")
  end

  # The '+ slot' button on the board links here with a date, and a bad or absent
  # date must not 500 the page.
  def test_new_event_accepts_and_survives_a_date_param
    get_ok('/events/new?date=2026-09-20')
    get_ok('/events/new?date=not-a-date')
  end

  def test_users_page_filters_all_render
    UsersIndex::FILTERS.each { |value, _| get_ok("/users?filter=#{value}") }
    get_ok('/users?q=coord')
  end

  def test_unknown_record_is_not_found_rather_than_a_crash
    as_leader
    get '/events/999999'
    refute_equal 500, last_response.status
    get '/users/999999'
    refute_equal 500, last_response.status
  end

  def test_logged_out_visitor_is_sent_to_login
    env 'rack.session', {}
    get '/board'
    assert_equal 302, last_response.status
    assert_includes last_response.location.to_s, '/login'
  end

  def test_login_page_is_public
    env 'rack.session', {}
    get '/login'
    assert last_response.ok?
  end

  # --- the sign-up post lifecycle -----------------------------------------
  #
  # This is the flow the whole feature hangs off: compose a post, give it
  # options, schedule it, and have the publisher pick it up. Each step is a
  # separate route and they were only ever exercised by hand.

  def test_a_signup_post_can_be_composed_scheduled_and_becomes_publishable
    as_leader
    post '/signups', channel_id: channel.id, service_date: Time.zone.today.to_s
    assert_includes [200, 302], last_response.status, last_response.body.to_s[0, 400]

    record = SignupPost.order(:id).last
    refute_nil record, 'POST /signups created nothing'

    as_leader
    post "/signups/#{record.id}/options", emoji: '1️⃣', event_id: @event.id, label: 'Early ride'
    assert_equal 1, record.reload.options.count, 'the option was not added'

    option = record.options.first
    assert_equal '1️⃣', option.emoji_unicode
    assert_equal @event, option.event, 'the option must be linked to the ride it books'

    # The settings form saves the send time, then a separate button schedules.
    as_leader
    patch "/signups/#{record.id}", post_at: 1.hour.from_now.strftime('%Y-%m-%dT%H:%M'),
                                   channel_id: channel.id, service_date: Time.zone.today.to_s
    refute_nil record.reload.post_at, 'PATCH did not save the send time'

    as_leader
    post "/signups/#{record.id}/schedule"
    record.reload
    assert_equal 'scheduled', record.status
    refute_nil record.post_at

    # Due posts are what the bot's publisher actually looks for.
    record.update!(post_at: 1.minute.ago)
    assert_includes SignupPost.due, record
  end

  def test_scheduling_accepts_a_send_time_given_inline
    as_leader
    post '/signups', channel_id: channel.id, service_date: Time.zone.today.to_s
    record = SignupPost.order(:id).last
    as_leader
    post "/signups/#{record.id}/options", emoji: '1️⃣', event_id: @event.id

    as_leader
    post "/signups/#{record.id}/schedule", post_at: 1.hour.from_now.strftime('%Y-%m-%dT%H:%M')

    assert_equal 'scheduled', record.reload.status,
                 'a time passed to schedule must not be silently discarded'
  end

  def test_the_rendered_body_contains_each_option
    as_leader
    post '/signups', channel_id: channel.id, service_date: Time.zone.today.to_s
    record = SignupPost.order(:id).last
    as_leader
    post "/signups/#{record.id}/options", emoji: '1️⃣', event_id: @event.id, label: 'Early ride'

    body = record.reload.body
    assert_includes body, '1️⃣'
    assert_includes body, 'Early ride'
  end

  # --- the emoji picker ----------------------------------------------------

  def test_an_emoji_chosen_from_the_picker_is_accepted
    record = draft_post

    as_leader
    post "/signups/#{record.id}/options", emoji_pick: '🚗', event_id: @event.id

    assert_equal 1, record.reload.options.count
    assert_equal '🚗', record.options.first.emoji_unicode
  end

  def test_the_picker_offers_this_servers_custom_emoji
    emoji = Emoji.create!(name: 'abide_car', discord_id: custom_emoji_id, server: channel.server)
    record = draft_post

    body = get_ok("/signups/#{record.id}").body

    assert_includes body, "<:#{emoji.name}:#{emoji.discord_id}>",
                    'a custom emoji must be offered in the form Discord uses'
    assert_includes body, "cdn.discordapp.com/emojis/#{emoji.discord_id}"
  end

  def test_a_custom_server_emoji_can_be_chosen
    emoji = Emoji.create!(name: 'abide_car', discord_id: custom_emoji_id, server: channel.server)
    record = draft_post

    as_leader
    post "/signups/#{record.id}/options",
         emoji_pick: "<:#{emoji.name}:#{emoji.discord_id}>", event_id: @event.id

    option = record.reload.options.first
    refute_nil option, 'a custom server emoji must be usable as a sign-up option'
    assert_equal emoji.discord_id, option.emoji_discord_id
    assert_equal "c:#{emoji.discord_id}", option.emoji_key
  end

  def test_a_custom_emoji_renders_as_an_image_not_a_raw_token
    emoji = Emoji.create!(name: 'abide_car', discord_id: custom_emoji_id, server: channel.server)
    record = draft_post
    as_leader
    post "/signups/#{record.id}/options",
         emoji_pick: "<:#{emoji.name}:#{emoji.discord_id}>", event_id: @event.id

    body = get_ok("/signups/#{record.id}").body

    # The message the bot sends still carries the token; the page must not show
    # it as text, in the option row or in the preview.
    assert_includes record.reload.body, "<:#{emoji.name}:#{emoji.discord_id}>"
    refute_includes body, ">&lt;:#{emoji.name}:", 'the raw token leaked into the rendered page'
    assert_operator body.scan("cdn.discordapp.com/emojis/#{emoji.discord_id}").size, :>=, 2,
                    'expected the image in both the option row and the preview'
  end

  def test_typed_text_wins_over_a_picked_emoji
    record = draft_post

    as_leader
    post "/signups/#{record.id}/options", emoji: '✅', emoji_pick: '🚗', event_id: @event.id

    assert_equal '✅', record.reload.options.first.emoji_unicode
  end

  def test_a_nonsense_emoji_is_rejected_rather_than_stored
    as_leader
    post '/signups', channel_id: channel.id, service_date: Time.zone.today.to_s
    record = SignupPost.order(:id).last

    as_leader
    post "/signups/#{record.id}/options", emoji: 'garbage!!', event_id: @event.id
    assert_equal 0, record.reload.options.count
  end

  private

  # EmojiKey's <:name:id> pattern requires a real snowflake (15-25 digits), so
  # the short synthetic ids the other tests use would not parse.
  def custom_emoji_id = 1_141_575_602_231_582_782 + (@discord_seq += 1)

  def draft_post
    as_leader
    post '/signups', channel_id: channel.id, service_date: Time.zone.today.to_s
    SignupPost.order(:id).last
  end

  def channel
    @channel ||= begin
      server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
      Channel.create!(name: 'bot', discord_id: next_discord_id, server: server)
    end
  end
end
