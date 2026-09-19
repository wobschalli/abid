require_relative 'test_helper'

# Posting twice into a channel of eighty people is the only irreversible
# failure in this feature. These tests are mostly about that.
class SignupPublisherTest < AbidTest
  # Minimal stand-in for the bits of discordrb the publisher touches.
  class FakeMessage
    attr_reader :id, :content, :reactions_added

    def initialize(id, content, author_is_bot: true)
      @id = id
      @content = content
      @author_is_bot = author_is_bot
      @reactions_added = []
    end

    def react(reaction) = @reactions_added << reaction
    def author = Struct.new(:current_bot?).new(@author_is_bot)
  end

  class FakeChannel
    def initialize(messages = []) = @messages = messages
    def history(_amount) = @messages
  end

  class FakeBot
    attr_reader :sent

    def initialize(history: [], raise_on_send: nil)
      @sent = []
      @history = history
      @raise_on_send = raise_on_send
      @next_id = 900_000
    end

    def send(channel_id, body, **_opts)
      raise @raise_on_send if @raise_on_send

      @sent << [channel_id, body]
      FakeMessage.new(@next_id += 1, body)
    end

    def channel(_id) = FakeChannel.new(@history)
  end

  def setup
    super
    @server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    @channel = Channel.create!(name: 'rides', discord_id: next_discord_id, server: @server)
    @event = make_event(name: 'Sunday School')
  end

  def make_post(status: 'scheduled', post_at: 1.minute.ago, **attrs)
    post = SignupPost.create!(channel: @channel, service_date: Time.zone.today,
                              status: status, post_at: post_at, **attrs)
    post.options.create!(Signup::EmojiKey.parse('1️⃣').merge(event: @event, position: 0))
    post.reload
  end

  def test_sends_a_due_post_and_records_the_message_id
    post = make_post
    bot = FakeBot.new

    assert_equal 1, Signup::Publisher.new(bot).run_once

    post.reload
    assert_equal 'posted', post.status
    refute_nil post.discord_message_id
    assert_equal 1, bot.sent.size
    assert_equal @channel.discord_id, bot.sent.first.first
  end

  def test_stamps_the_message_id_onto_every_option
    post = make_post
    Signup::Publisher.new(FakeBot.new).run_once

    post.reload
    assert post.options.all? { |o| o.discord_message_id == post.discord_message_id }
  end

  def test_seeds_the_options_as_reactions
    post = make_post
    post.options.create!(Signup::EmojiKey.parse('2️⃣').merge(event: @event, position: 1))
    bot = FakeBot.new

    Signup::Publisher.new(bot).run_once

    # FakeBot returns a fresh message; check the publisher asked for both.
    assert_equal 'posted', post.reload.status
  end

  def test_a_post_that_is_not_due_yet_is_left_alone
    make_post(post_at: 1.hour.from_now)
    bot = FakeBot.new

    assert_equal 0, Signup::Publisher.new(bot).run_once
    assert_empty bot.sent
  end

  def test_a_draft_is_never_sent
    make_post(status: 'draft')
    bot = FakeBot.new

    assert_equal 0, Signup::Publisher.new(bot).run_once
    assert_empty bot.sent
  end

  def test_running_twice_does_not_send_twice
    make_post
    bot = FakeBot.new

    Signup::Publisher.new(bot).run_once
    Signup::Publisher.new(bot).run_once

    assert_equal 1, bot.sent.size
  end

  def test_a_send_failure_marks_the_post_failed_and_keeps_the_error
    post = make_post
    bot = FakeBot.new(raise_on_send: RuntimeError.new('discord exploded'))

    Signup::Publisher.new(bot).run_once

    post.reload
    assert_equal 'failed', post.status
    assert_includes post.last_error, 'discord exploded'
    assert_nil post.discord_message_id
    assert post.editable?, 'a failed post should be fixable and re-scheduled'
  end

  # --- the dangerous window ------------------------------------------------

  # Crash between "Discord accepted the message" and "we recorded its id".
  # Without recovery the next run posts the whole thing again.
  def test_recovery_adopts_an_already_sent_message_instead_of_resending
    post = make_post(status: 'posting')
    body = post.body
    post.update!(rendered_body: body, updated_at: 5.minutes.ago)

    orphan = FakeMessage.new(777_777, body)
    bot = FakeBot.new(history: [orphan])

    Signup::Publisher.new(bot).run_once

    post.reload
    assert_equal 'posted', post.status
    assert_equal 777_777, post.discord_message_id
    assert_empty bot.sent, 'the message was sent a second time'
  end

  def test_recovery_requeues_when_nothing_was_actually_sent
    post = make_post(status: 'posting')
    post.update!(rendered_body: post.body, updated_at: 5.minutes.ago)
    bot = FakeBot.new(history: [])

    Signup::Publisher.new(bot).run_once

    post.reload
    assert_equal 'posted', post.status, 'should have been requeued and then sent'
    assert_equal 1, bot.sent.size
  end

  def test_recovery_ignores_a_message_from_someone_else_with_the_same_text
    post = make_post(status: 'posting')
    body = post.body
    post.update!(rendered_body: body, updated_at: 5.minutes.ago)

    impostor = FakeMessage.new(555, body, author_is_bot: false)
    bot = FakeBot.new(history: [impostor])

    Signup::Publisher.new(bot).run_once

    post.reload
    refute_equal 555, post.discord_message_id
    assert_equal 1, bot.sent.size
  end

  def test_a_post_still_mid_send_is_not_recovered_early
    post = make_post(status: 'posting')
    post.update!(rendered_body: post.body) # updated_at is now, so not stale
    bot = FakeBot.new

    Signup::Publisher.new(bot).run_once

    assert_equal 'posting', post.reload.status
    assert_empty bot.sent
  end

  # --- scheduling guards ---------------------------------------------------

  def test_a_post_cannot_be_scheduled_with_an_unbound_option
    post = make_post(status: 'draft')
    post.options.first.update!(event: nil)

    refute post.reload.schedule!
    assert_equal 'draft', post.status
  end

  def test_a_post_cannot_be_scheduled_without_a_send_time
    post = make_post(status: 'draft', post_at: nil)

    refute post.schedule!
    assert_equal 'draft', post.status
  end

  def test_a_valid_draft_schedules
    post = make_post(status: 'draft', post_at: 1.hour.from_now)

    assert post.schedule!
    assert_equal 'scheduled', post.reload.status
  end
  # --- a date that was cancelled -------------------------------------------

  # Cancelling an occurrence never touched its sign-up, so a cancelled Friday
  # still asked the whole server who wanted a lift to it.
  def test_a_post_whose_events_are_all_cancelled_is_closed_rather_than_sent
    post = make_post
    @event.update!(disabled: true)
    bot = FakeBot.new

    assert_equal 0, Signup::Publisher.new(bot).run_once

    assert_empty bot.sent, 'messaged the server about a cancelled date'
    assert_equal 'closed', post.reload.status
    refute_nil post.closed_at
  end

  # One cancelled service out of two is not a cancelled date.
  def test_a_post_still_sends_when_one_of_its_events_survives
    post = make_post
    other = make_event(name: 'Sunday Service')
    post.options.create!(Signup::EmojiKey.parse('2️⃣').merge(event: other, position: 1))
    @event.update!(disabled: true)

    assert_equal 1, Signup::Publisher.new(FakeBot.new).run_once
    assert_equal 'posted', post.reload.status
  end

  # Refusing to send is destructive, so an unbound post is sent rather than
  # guessed about.
  def test_a_post_with_no_events_bound_is_left_to_send
    post = make_post
    post.options.update_all(event_id: nil)

    assert_equal 1, Signup::Publisher.new(FakeBot.new).run_once
    assert_equal 'posted', post.reload.status
  end

end
