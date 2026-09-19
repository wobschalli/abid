require_relative 'test_helper'
# The reconciler resolves these error classes lazily, precisely so the web
# process need not load discordrb — but this test asserts on them by name, so
# here it is required explicitly.
require 'discordrb'

# The reconciler is the safety net for dropped gateway events, so its failure
# modes matter more than its happy path: treating a network blip as a deletion
# would silently strand riders, and treating a deletion as a blip made the bot
# re-fetch a dead message every tick for the rest of the semester.
class SignupReconcilerTest < AbidTest
  # Stands in for a Discord message with no reactions on it.
  class FakeMessage
    def reactions = []
  end

  class FakeChannel
    def initialize(message, raise_with) = (@message, @raise_with = message, raise_with)

    def load_message(_id)
      raise @raise_with if @raise_with

      @message
    end
  end

  # `visible: false` makes `bot.channel` return nil, which is what discordrb
  # really does for a channel the bot cannot see — it does not raise.
  class FakeBot
    def initialize(raise_with: nil, visible: true, message: :default)
      @raise_with = raise_with
      @visible = visible
      # `message: nil` is how the real library reports a message that does not
      # exist — see the test at the bottom of this file.
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
                               status: 'posted', discord_message_id: next_discord_id)
    @post.options.create!(Signup::EmojiKey.parse('1️⃣').merge(event: @event, position: 0))
    @post.reload
  end

  # The reconciler warns on every failure path; keep the test output readable
  # while still returning the report.
  def reconcile(bot)
    report = nil
    capture_io { report = Signup::Reconciler.new(bot).run(@post) }
    report
  end

  def test_closes_a_post_whose_channel_the_bot_cannot_see
    # This used to surface as `NoMethodError: undefined method 'load_message'
    # for nil`, which reads like a code bug and names neither the post nor the
    # channel actually at fault.
    report = reconcile(FakeBot.new(visible: false))

    assert_equal :message_gone, report.status
    assert_equal 'closed', @post.reload.status
  end

  def test_closes_a_post_whose_message_was_deleted
    reconcile(FakeBot.new(raise_with: Discordrb::Errors::UnknownMessage.new('unknown message')))

    @post.reload
    assert_equal 'closed', @post.status
    assert_match(/no longer exists/, @post.last_error)
    refute_includes SignupPost.tracking, @post
  end

  def test_keeps_tracking_through_a_transient_failure
    # The important half. A 500 or a dropped socket must not close the post —
    # doing so would freeze the board mid-sign-up with nothing to notice it.
    report = reconcile(FakeBot.new(raise_with: RuntimeError.new('Gateway timeout')))

    assert_equal :message_gone, report.status
    assert_equal 'posted', @post.reload.status, 'transient failure must not close the post'
    assert_includes SignupPost.tracking, @post
  end

  def test_a_reachable_message_reconciles_normally
    report = reconcile(FakeBot.new)

    assert_equal :ok, report.status
    assert_equal 'posted', @post.reload.status
    refute_nil @post.reconciled_at
  end
  # The real Discordrb::Channel#load_message rescues UnknownMessage and returns
  # nil, so the exception this class waits for never escapes in production.
  # Every "message is gone" test here raises instead, which is why the branch
  # could not fire against a live bot and still tested green.
  def test_a_message_discord_returns_as_nil_stops_the_polling
    bot = FakeBot.new(message: nil)

    capture_io { @report = Signup::Reconciler.new(bot).run(@post) }

    assert_equal :message_gone, @report.status
    @post.reload
    assert_equal 'closed', @post.status, 'kept polling a message that does not exist'
    assert_equal false, @post.reconcile_ok
  end

end
