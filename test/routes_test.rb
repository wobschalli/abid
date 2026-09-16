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
    %w[/ /board /schedule /locations /users].each { |path| get_ok(path) }
  end

  # Events, Series and Sign-ups are one page now. The old paths still work so
  # bookmarks and any link out in the wild do not break.
  def test_the_three_old_index_paths_redirect_to_the_schedule
    %w[/events /series /signups].each do |path|
      as_leader
      get path
      assert_equal 302, last_response.status, path
      assert_includes last_response.location, '/schedule'
    end
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
    get_ok('/schedule')
    get_ok("/events/#{@event.id}/dispatches")
  end

  def test_csv_exports_render
    assert_equal 'text/csv', get_ok("/events/#{@event.id}.csv").content_type.split(';').first
    get_ok("/board/#{@event.id}.csv")
  end

  # /events/new takes an optional date. Nothing links to it with one any more
  # (the board's '+ slot' did, and is now next/previous arrows), but the param
  # is still supported and a bad one must not 500 the page.
  def test_new_event_accepts_and_survives_a_date_param
    get_ok('/events/new?date=2026-09-20')
    get_ok('/events/new?date=not-a-date')
  end

  def test_users_page_filters_all_render
    UsersIndex::FILTERS.each { |value, _| get_ok("/users?filter=#{value}") }
    get_ok('/users?q=coord')
  end

  def test_members_defaults_to_active_and_has_no_everyone_tab
    body = get_ok('/users').body

    refute_includes UsersIndex::FILTERS.map(&:first), 'all'
    assert_includes body, 'Active'
    assert_includes body, 'Non-Active'
  end

  # Drivers / Riders / Missing details describe the active roster, not everyone
  # who has ever been in the Discord.
  def test_the_member_tabs_are_cuts_of_the_active_roster
    User.create!(name: 'Active driver', username: 'ad', discord_id: next_discord_id,
                 password: 'x' * 10, capacity: 4, active: true)
    User.create!(name: 'Alum driver', username: 'alumd', discord_id: next_discord_id,
                 password: 'x' * 10, capacity: 4)

    names = ->(f) { get_ok("/users?filter=#{f}").body }

    assert_includes names.call('drivers'), 'Active driver'
    refute_includes names.call('drivers'), 'Alum driver'
    refute_includes names.call('riders'), 'Alum driver'
    refute_includes names.call('missing'), 'Alum driver'
    assert_includes names.call('other'), 'Alum driver'
  end

  def test_one_click_marks_a_member_active_and_back
    member = User.create!(name: 'Laura', username: 'laura', discord_id: next_discord_id,
                          password: 'x' * 10)

    as_leader
    post "/users/#{member.id}/active", active: '1'
    assert member.reload.active?

    as_leader
    post "/users/#{member.id}/active", active: '0'
    refute member.reload.active?
  end

  def test_the_toggle_returns_to_the_tab_you_were_on
    # Marking a dozen people active in a row must not bounce you back to the
    # top of an unfiltered list each time.
    member = User.create!(name: 'Laura', username: 'laura', discord_id: next_discord_id,
                          password: 'x' * 10)

    as_leader
    post "/users/#{member.id}/active", active: '1', filter: 'other', q: 'rach'

    assert_equal 302, last_response.status
    assert_includes last_response.location, 'filter=other'
    assert_includes last_response.location, 'q=rach'
  end

  def test_a_member_cannot_be_marked_active_by_a_non_leader
    member = User.create!(name: 'Laura', username: 'laura', discord_id: next_discord_id,
                          password: 'x' * 10)
    plain_user = User.create!(name: 'Nobody', username: 'nobody', discord_id: next_discord_id,
                              password: 'x' * 10)

    env 'rack.session', { user_id: plain_user.id }
    post "/users/#{member.id}/active", active: '1'

    assert_equal 403, last_response.status
    refute member.reload.active?
  end

  def test_the_profile_checkbox_saves_active
    member = User.create!(name: 'Laura', username: 'laura', discord_id: next_discord_id,
                          password: 'x' * 10)

    as_leader
    patch "/users/#{member.id}", name: 'Laura', active: '1'
    assert member.reload.active?

    # Unticked checkboxes are absent from params; the hidden '0' is what turns
    # it off, so this must not silently leave it on.
    as_leader
    patch "/users/#{member.id}", name: 'Laura', active: '0'
    refute member.reload.active?
  end

  # --- the weekly driver work ----------------------------------------------

  def test_a_rider_can_be_promoted_to_driver_in_place
    # Everyone who reacts arrives as a rider, so without this every driver had
    # to be deleted and re-added, every week.
    user = User.create!(name: 'Caleb', username: 'caleb', discord_id: next_discord_id,
                        password: 'x' * 10, capacity: 4)
    ride = @event.rides.create!(user: user, role: 'rider', status: 'requested')

    as_leader
    patch "/board/#{@event.id}/rides/#{ride.id}", role: 'driver'

    ride.reload
    assert_equal 'driver', ride.role
    assert_equal 4, ride.seats, 'a promoted driver needs seats or the car has none'
  end

  def test_a_nonsense_role_is_ignored_rather_than_crashing
    user = User.create!(name: 'Caleb', username: 'caleb2', discord_id: next_discord_id,
                        password: 'x' * 10)
    ride = @event.rides.create!(user: user, role: 'rider', status: 'requested')

    as_leader
    patch "/board/#{@event.id}/rides/#{ride.id}", role: 'astronaut'

    refute_equal 500, last_response.status
    assert_equal 'rider', ride.reload.role
  end

  def test_one_press_seats_every_regular_driver
    drives = User.create!(name: 'Caleb', username: 'caleb3', discord_id: next_discord_id,
                          password: 'x' * 10, capacity: 4, active: true)
    User.create!(name: 'Passenger', username: 'pax', discord_id: next_discord_id,
                 password: 'x' * 10, active: true)
    User.create!(name: 'Alum', username: 'alum', discord_id: next_discord_id,
                 password: 'x' * 10, capacity: 4)

    as_leader
    post "/board/#{@event.id}/drivers"

    roles = @event.rides.reload.includes(:user).map { |r| [r.user.name, r.role] }
    assert_equal [['Caleb', 'driver']], roles,
                 'only active members with seats, and nobody twice'
    assert_equal 4, @event.rides.first.seats
  end

  def test_adding_regular_drivers_twice_does_not_duplicate_anyone
    User.create!(name: 'Caleb', username: 'caleb4', discord_id: next_discord_id,
                 password: 'x' * 10, capacity: 4, active: true)

    as_leader
    post "/board/#{@event.id}/drivers"
    as_leader
    post "/board/#{@event.id}/drivers"

    assert_equal 1, @event.rides.reload.count
  end

  # --- locations -----------------------------------------------------------

  def test_a_location_address_can_be_saved
    place = Location.create!(name: 'Third and West', zone: Location::ZONES.first)

    as_leader
    patch "/locations/#{place.id}", address: 'West Third Street'

    assert_equal 'West Third Street', place.reload.address
  end

  def test_the_geocode_query_prefers_the_address_over_the_name
    # OSM has never heard of "Third and West" — querying it unbounded returns
    # nothing. It knows the street it stands on.
    place = Location.new(name: 'Third and West', address: 'West Third Street')
    assert_equal 'West Third Street, West Lafayette, Indiana', place.geocode_query

    named = Location.new(name: 'Cary Quadrangle')
    assert_equal 'Cary Quadrangle, West Lafayette, Indiana', named.geocode_query
  end

  def test_a_non_leader_cannot_edit_a_location
    place = Location.create!(name: 'Somewhere', zone: Location::ZONES.first)
    plain_user = User.create!(name: 'Nobody', username: 'nobody2', discord_id: next_discord_id,
                              password: 'x' * 10)

    env 'rack.session', { user_id: plain_user.id }
    patch "/locations/#{place.id}", address: 'hacked'

    assert_equal 403, last_response.status
    assert_nil place.reload.address
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

  # --- post now ------------------------------------------------------------
  #
  # The web process has no Discord connection, so "send" can only mean "make
  # the row claimable by the bot". These assert exactly that and stop there —
  # nothing is posted to a real server.

  def test_post_now_makes_a_draft_claimable_by_the_bot
    record = draft_post
    as_leader
    post "/signups/#{record.id}/options", emoji: '1️⃣', event_id: @event.id

    as_leader
    post "/signups/#{record.id}/post-now"

    record.reload
    assert_equal 'scheduled', record.status
    refute_nil record.post_at
    assert_operator record.post_at, :<=, Time.zone.now
    assert_includes SignupPost.due, record, 'the bot must be able to claim it'
  end

  def test_post_now_brings_a_scheduled_post_forward
    record = draft_post
    as_leader
    post "/signups/#{record.id}/options", emoji: '1️⃣', event_id: @event.id
    record.update!(post_at: 3.days.from_now, status: 'scheduled')

    as_leader
    post "/signups/#{record.id}/post-now"

    record.reload
    assert_equal 'scheduled', record.status
    assert_operator record.post_at, :<=, Time.zone.now
    assert_includes SignupPost.due, record
  end

  def test_post_now_refuses_a_post_with_no_rides
    record = draft_post

    as_leader
    post "/signups/#{record.id}/post-now"

    assert_equal 422, last_response.status
    refute_equal 'scheduled', record.reload.status
    refute_includes SignupPost.due, record
  end

  def test_post_now_refuses_a_post_already_sent
    record = draft_post
    record.update!(status: 'posted', discord_message_id: next_discord_id)

    as_leader
    post "/signups/#{record.id}/post-now"

    assert_equal 409, last_response.status
  end

  def test_a_permission_failure_says_what_to_fix
    record = draft_post
    as_leader
    post "/signups/#{record.id}/options", emoji: '1️⃣', event_id: @event.id
    record.update!(status: 'failed',
                   last_error: "Discordrb::Errors::NoPermission: The bot doesn't have the required permission to do this!")

    body = get_ok("/signups/#{record.id}").body

    # Discord's own wording names neither the permission nor the channel.
    assert_includes body, "cannot post in ##{channel.name}"
    assert_includes body, 'Send Messages'
    assert_includes body, 'View Channel'
  end

  # --- one-click sign-ups --------------------------------------------------

  def test_creating_a_post_fills_in_that_days_rides
    day = @event.start_time.to_date
    as_leader
    post '/signups', channel_id: channel.id, service_date: day.to_s

    record = SignupPost.order(:id).last
    assert_equal 1, record.options.count, 'the post should arrive already filled in'
    assert_equal @event, record.options.first.event
    assert record.bound?
  end

  def test_the_ride_dropdown_is_scoped_to_the_posts_own_date
    # A second event on another day must not be offered.
    other = make_event(name: 'Friday Bible Study', starts: @event.start_time + 3.days)
    as_leader
    post '/signups', channel_id: channel.id, service_date: @event.start_time.to_date.to_s
    record = SignupPost.order(:id).last

    body = get_ok("/signups/#{record.id}").body

    assert_includes body, "value=\"#{@event.id}\""
    refute_includes body, "value=\"#{other.id}\"",
                    'an event on another day must not clutter the picker'
  end

  def test_the_dropdown_still_offers_an_event_an_option_already_points_at
    # Narrowing the list must not orphan an existing binding: if the selected
    # event is missing from the options, the select renders blank and the next
    # Save silently rebinds the ride to something else.
    other = make_event(name: 'Friday Bible Study', starts: @event.start_time + 3.days)
    as_leader
    post '/signups', channel_id: channel.id, service_date: @event.start_time.to_date.to_s
    record = SignupPost.order(:id).last
    record.options.first.update!(event: other)

    body = get_ok("/signups/#{record.id}").body

    assert_includes body, "value=\"#{other.id}\""
  end

  def test_the_schedule_offers_to_create_a_signup_for_an_uncovered_date
    body = get_ok('/schedule').body

    assert_includes body, @event.start_time.strftime('%A %-d %B')
    assert_includes body, 'Create'
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
