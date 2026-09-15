require_relative 'test_helper'

# The edge cases that decide whether the board can be trusted on a Sunday
# morning. Every one of these is reachable from a single mis-tap in Discord.
class SignupReactionSinkTest < AbidTest
  MESSAGE_ID = 987_654_321_000_111_222

  def setup
    super
    @sink = Signup::ReactionSink.new
    @event = make_event(name: 'Sunday School')
    @post = make_post
    @option = make_option(@post, 'u:one', @event)
  end

  # --- the happy path ------------------------------------------------------

  def test_a_reaction_creates_a_rider
    result = react('u:one', 4242, username: 'newcomer')

    assert_equal :created, result.status
    ride = result.ride
    assert_equal 'rider', ride.role
    assert_equal 'requested', ride.status
    assert_equal 'discord', ride.source
    assert_equal @event.id, ride.event_id
  end

  def test_an_unknown_discord_user_is_provisioned
    assert_difference_in_users(1) { react('u:one', 5150, username: 'ghost', display_name: 'Ghost') }

    user = User.find_by(discord_id: 5150)
    assert_equal 'ghost', user.username
    assert_equal 'Ghost', user.name
  end

  def test_an_existing_user_is_reused_not_duplicated
    existing = make_user('caitlin')
    assert_difference_in_users(0) { react('u:one', existing.discord_id) }

    assert_equal existing.id, @event.rides.first.user_id
  end

  # Discord redelivers events on gateway resume.
  def test_a_duplicate_reaction_is_idempotent
    react('u:one', 4242)
    result = react('u:one', 4242)

    assert_equal :duplicate, result.status
    assert_equal 1, @event.rides.count
    assert_equal 1, @option.signup_reactions.count
  end

  # --- reactions we must ignore --------------------------------------------

  def test_a_reaction_on_another_message_is_ignored
    result = @sink.add(message_id: 111, emoji_key: 'u:one', discord_user_id: 4242)

    assert_equal :ignored, result.status
    assert_equal 0, @event.rides.count
  end

  def test_an_emoji_that_is_not_an_option_is_ignored
    result = react('u:pizza', 4242)

    assert_equal :ignored, result.status
    assert_equal 0, @event.rides.count
  end

  def test_a_bot_reaction_is_ignored
    result = react('u:one', 4242, bot: true)

    assert_equal :ignored, result.status
    assert_equal 0, @event.rides.count
  end

  # --- post and option state -----------------------------------------------

  def test_a_closed_post_records_the_reaction_but_creates_no_ride
    @post.close!
    result = react('u:one', 4242)

    assert_equal :closed, result.status
    assert_equal 0, @event.rides.count
    # Still recorded, so the coordinator can see who tried.
    assert_equal 1, @option.signup_reactions.count
  end

  def test_an_unbound_option_records_the_reaction_but_creates_no_ride
    orphan = make_option(@post, 'u:two', nil)
    result = react('u:two', 4242)

    assert_equal :unbound, result.status
    assert_equal 1, orphan.signup_reactions.count
    assert_equal 0, Ride.count
  end

  # --- two options ---------------------------------------------------------

  def test_two_options_on_different_events_make_two_rides
    other_event = make_event(name: 'Sunday Service')
    make_option(@post, 'u:two', other_event)

    react('u:one', 4242)
    react('u:two', 4242)

    assert_equal 1, @event.rides.count
    assert_equal 1, other_event.rides.count
  end

  # "Either time works for me" — the ride must survive losing one of them.
  def test_two_options_on_the_same_event_share_one_ride
    make_option(@post, 'u:two', @event)

    react('u:one', 4242)
    react('u:two', 4242)
    assert_equal 1, @event.rides.count

    unreact('u:one', 4242)
    assert_equal 1, @event.rides.count, 'ride died while a second reaction still backed it'

    unreact('u:two', 4242)
    assert_equal 0, @event.rides.count
  end

  # --- un-reacting ---------------------------------------------------------

  def test_unreacting_before_being_seated_removes_the_ride
    react('u:one', 4242)
    result = unreact('u:one', 4242)

    assert_equal :cancelled, result.status
    assert_equal 0, @event.rides.count
  end

  # The decision: flag, do not silently empty a car the coordinator planned.
  def test_unreacting_after_being_seated_frees_the_seat_but_keeps_the_row
    rider = react('u:one', 4242).ride
    driver = make_driver_ride
    rider.update!(driver_ride_id: driver.id, status: 'assigned')

    result = unreact('u:one', 4242)

    assert_equal :dropped, result.status
    rider.reload
    assert_equal 'no_show', rider.status
    assert_nil rider.driver_ride_id
    assert rider.dropped?
    assert_equal 0, driver.passengers.active.count
    # The row survives — visibly dropped, not silently gone.
    assert_equal 1, @event.rides.riders.count
  end

  def test_re_reacting_after_dropping_out_brings_them_back
    react('u:one', 4242)
    unreact('u:one', 4242)
    assert_equal 0, @event.rides.count

    result = react('u:one', 4242)
    assert_equal :created, result.status
    assert_equal 'requested', result.ride.status
  end

  def test_re_reacting_after_being_marked_no_show_clears_the_drop
    rider = react('u:one', 4242).ride
    driver = make_driver_ride
    rider.update!(driver_ride_id: driver.id, status: 'assigned')
    unreact('u:one', 4242)

    result = react('u:one', 4242)

    assert_equal :reactivated, result.status
    rider.reload
    assert_equal 'requested', rider.status
    assert_nil rider.dropped_at
  end

  def test_unreacting_twice_is_harmless
    react('u:one', 4242)
    unreact('u:one', 4242)
    result = unreact('u:one', 4242)

    assert_equal :ignored, result.status
  end

  # --- the ownership boundary ----------------------------------------------

  def test_a_coordinator_added_rider_is_never_removed_by_an_unreact
    user = make_user('manual rider')
    manual = @event.rides.create!(user: user, role: 'rider', status: 'requested', source: 'manual')

    react('u:one', user.discord_id)
    result = unreact('u:one', user.discord_id)

    assert_equal :ignored, result.status
    assert Ride.exists?(manual.id), 'a manually added rider was deleted by Discord traffic'
  end

  def test_a_coordinator_added_rider_is_not_re_roled_by_a_reaction
    user = make_user('a driver')
    driver = @event.rides.create!(user: user, role: 'driver', status: 'confirmed',
                                  seats: 4, source: 'manual')

    result = react('u:one', user.discord_id)

    assert_equal :ignored, result.status
    assert_equal 'driver', driver.reload.role
  end

  def test_a_driver_is_never_deleted_by_unreacting
    user = make_user('driver')
    driver = @event.rides.create!(user: user, role: 'driver', status: 'confirmed',
                                  seats: 4, source: 'discord')
    react('u:one', user.discord_id)

    unreact('u:one', user.discord_id)

    assert Ride.exists?(driver.id), 'a driver was removed, emptying their car'
  end

  # --- clearing every reaction ---------------------------------------------

  def test_remove_all_clears_every_live_reaction
    make_option(@post, 'u:two', make_event(name: 'Other'))
    react('u:one', 4242)
    react('u:two', 5150)

    @sink.remove_all(message_id: MESSAGE_ID)

    assert_equal 0, Ride.where(source: 'discord').count
    assert_equal 0, SignupReaction.live.count
  end

  private

  def react(emoji_key, discord_user_id, **opts)
    @sink.add(message_id: MESSAGE_ID, emoji_key: emoji_key,
              discord_user_id: discord_user_id, **opts)
  end

  def unreact(emoji_key, discord_user_id)
    @sink.remove(message_id: MESSAGE_ID, emoji_key: emoji_key, discord_user_id: discord_user_id)
  end

  def make_post
    server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    channel = Channel.create!(name: 'rides', discord_id: next_discord_id, server: server)
    SignupPost.create!(channel: channel, discord_message_id: MESSAGE_ID,
                       status: 'posted', posted_at: Time.zone.now)
  end

  def make_option(post, emoji_key, event)
    post.options.create!(
      emoji_key: emoji_key,
      emoji_unicode: emoji_key.sub('u:', ''),
      emoji_name: emoji_key.sub('u:', ''),
      event: event,
      position: post.options.count,
      discord_message_id: post.discord_message_id
    )
  end

  def make_driver_ride
    @event.rides.create!(user: make_user('wheels', capacity: 4), role: 'driver',
                         status: 'confirmed', seats: 4, source: 'manual')
  end

  def assert_difference_in_users(count)
    before = User.count
    yield
    assert_equal count, User.count - before
  end
end
