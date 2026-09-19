require_relative 'test_helper'
# Asserted on by name below, and resolved lazily in MessageLookup so the web
# process need not load discordrb.
require 'discordrb'

# Unsending a sign-up is the one irreversible thing a coordinator can do from
# the dashboard, so the failure modes matter more than the happy path. Two in
# particular:
#
#   - the post must stay `posted` unless the message is really gone, or a bot
#     having a bad minute leaves you editing a draft whose original is still
#     live in the channel — and Post now then sends a SECOND one
#   - the reactions must be cleared through the sink, which protects drivers,
#     hand-added riders and anyone already seated
class SignupRevokerTest < AbidTest
  class FakeMessage
    attr_reader :deleted

    def initialize = (@deleted = false)
    def delete = (@deleted = true)
  end

  # Mirrors discordrb: a message that does not exist comes back as nil, NOT as
  # a raised UnknownMessage — Discordrb::Channel#load_message rescues that one
  # itself. A fake that raises instead is what let a real bug test green.
  class FakeChannel
    def initialize(message, raise_with) = (@message, @raise_with = message, raise_with)

    def load_message(_id)
      raise @raise_with if @raise_with

      @message
    end
  end

  class FakeBot
    attr_reader :message

    def initialize(raise_with: nil, visible: true, message: :default)
      @raise_with = raise_with
      @visible = visible
      # `message: nil` means "Discord has no such message", which is different
      # from "not specified".
      @message = message == :default ? FakeMessage.new : message
    end

    def channel(_id)
      return nil unless @visible

      FakeChannel.new(@message, @raise_with)
    end
  end

  def setup
    super
    @server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    @channel = Channel.create!(name: 'rides', discord_id: next_discord_id, server: @server)
    @event = make_event(name: 'Sunday School')
    @post = SignupPost.create!(channel: @channel, service_date: Time.zone.today,
                               status: 'posted', discord_message_id: next_discord_id,
                               posted_at: Time.zone.now, rendered_body: 'the old wrong text',
                               revoke_requested_at: Time.zone.now)
    @option = @post.options.create!(
      Signup::EmojiKey.parse('1️⃣').merge(event: @event, position: 0,
                                         discord_message_id: @post.discord_message_id)
    )
    @post.reload
  end

  def react(name)
    user = make_user(name)
    Signup::ReactionSink.new.add(message_id: @post.discord_message_id,
                                 emoji_key: @option.emoji_key,
                                 discord_user_id: user.discord_id, username: name)
    user
  end

  def revoke(bot) = Signup::Revoker.new(bot).run(@post)

  # --- the happy path -------------------------------------------------------

  def test_deletes_the_message_and_returns_the_post_to_a_draft
    bot = FakeBot.new

    result = capture_io { @result = revoke(bot) }.then { @result }

    assert_equal :revoked, result.status
    assert bot.message.deleted, 'the message was left in the channel'

    @post.reload
    assert_equal 'draft', @post.status
    assert_nil @post.discord_message_id
    assert_nil @post.posted_at
    assert_nil @post.revoke_requested_at
    # The option's copy has to go too: it is the key every reaction lookup uses.
    assert_nil @option.reload.discord_message_id
  end

  def test_the_draft_can_be_sent_again
    capture_io { revoke(FakeBot.new) }

    @post.reload
    assert @post.editable?, 'the whole point is being able to fix it and send it again'
    assert @post.ready_to_send?
  end

  # --- what happens to the people who already reacted ----------------------

  def test_an_unseated_rider_who_reacted_is_removed
    rider = react('caitlin')
    assert Ride.exists?(user_id: rider.id, event_id: @event.id)

    capture_io { revoke(FakeBot.new) }

    refute Ride.exists?(user_id: rider.id, event_id: @event.id),
           'left someone signed up to a message that no longer exists'
    assert_equal 0, @post.reload.live_reaction_count
  end

  # The sink refuses to delete a driver, because that silently empties a car
  # somebody has planned around.
  def test_a_driver_survives
    driver = react('ian')
    ride = Ride.find_by(user_id: driver.id, event_id: @event.id)
    ride.update!(role: 'driver', seats: 4)

    capture_io { revoke(FakeBot.new) }

    assert Ride.exists?(ride.id), 'deleted a driver out of a planned car'
  end

  # A rider already in a car is kept visible as a no-show rather than vanishing.
  def test_a_seated_rider_is_kept_as_a_no_show_with_the_seat_freed
    driver_ride = make_driver(@event, 'ian', seats: 4)
    rider = react('caitlin')
    ride = Ride.find_by(user_id: rider.id, event_id: @event.id)
    ride.update!(driver_ride: driver_ride, status: 'assigned')

    capture_io { revoke(FakeBot.new) }

    ride.reload
    assert_equal 'no_show', ride.status
    assert_nil ride.driver_ride_id, 'the seat was not freed'
  end

  def test_a_rider_the_coordinator_added_by_hand_is_untouched
    user = make_user('added by hand')
    ride = @event.rides.create!(user: user, role: 'rider', status: 'requested', source: 'manual')

    capture_io { revoke(FakeBot.new) }

    assert Ride.exists?(ride.id), "touched a coordinator's own row"
  end

  # --- the failure modes that matter ---------------------------------------

  # Discord having a bad minute must NOT produce a draft, or Post now sends a
  # second message while the first is still up.
  def test_a_transient_failure_leaves_the_post_posted_and_retries
    bot = FakeBot.new(raise_with: RuntimeError.new('503'))

    result = capture_io { @r = revoke(bot) }.then { @r }

    assert_equal :deferred, result.status
    @post.reload
    assert_equal 'posted', @post.status
    refute_nil @post.discord_message_id
    refute_nil @post.revoke_requested_at, 'the request was dropped instead of retried'
  end

  def test_a_channel_the_bot_cannot_see_is_treated_as_gone
    # `bot.channel` returning nil is what discordrb really does here, and it is
    # permanent rather than transient — the message is unreachable for good.
    result = capture_io { @r = revoke(FakeBot.new(visible: false)) }.then { @r }

    assert_equal :already_gone, result.status
    assert_equal 'draft', @post.reload.status
  end

  # Deleted by hand in Discord first, then Revoke pressed. The end state is what
  # matters; being stuck with a post the app thinks is live is the bug.
  #
  # This is how the real library reports it: nil, not an exception. Getting this
  # wrong meant the revoker retried a deleted message every fifteen seconds
  # forever, and it only showed up against a live bot.
  def test_a_message_discord_says_does_not_exist_completes
    bot = FakeBot.new(message: nil)

    result = capture_io { @r = revoke(bot) }.then { @r }

    assert_equal :already_gone, result.status
    @post.reload
    assert_equal 'draft', @post.status
    assert_nil @post.discord_message_id
  end

  # And if a future discordrb does raise it, that still counts as gone.
  def test_an_unknown_message_error_also_completes
    bot = FakeBot.new(raise_with: Discordrb::Errors::UnknownMessage.new(nil))

    result = capture_io { @r = revoke(bot) }.then { @r }

    assert_equal :already_gone, result.status
    assert_equal 'draft', @post.reload.status
  end

  # --- the scope the bot polls ---------------------------------------------

  def test_only_posts_asked_for_are_picked_up
    SignupPost.create!(channel: @channel, service_date: Time.zone.today + 1,
                       status: 'posted', discord_message_id: next_discord_id)

    assert_equal [@post.id], SignupPost.revoke_requested.pluck(:id)
  end

  # Stopping tracking does not take the message out of the channel, so a closed
  # post is still something you might need to take down.
  def test_a_closed_post_can_still_be_revoked
    @post.update!(status: 'closed', closed_at: Time.zone.now)

    assert_includes SignupPost.revoke_requested.pluck(:id), @post.id
    capture_io { revoke(FakeBot.new) }
    assert_equal 'draft', @post.reload.status
  end

  def test_a_draft_is_not_in_the_scope
    @post.update!(status: 'draft', discord_message_id: nil)

    refute_includes SignupPost.revoke_requested.pluck(:id), @post.id
  end
end
