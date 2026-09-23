require_relative 'test_helper'
# The view is resolved lazily so the web process need not load discordrb;
# without this require the button path would silently never run here.
require 'discordrb'

# Posted once, refreshed thereafter. A second copy would carry a second pair
# of buttons and two sources of truth for the same preference.
class SnipesNoticeTest < AbidTest
  class FakeSent
    attr_reader :id, :edits

    def initialize(id)
      @id = id
      @edits = []
    end

    def edit(content, embeds = nil, components = nil)
      @edits << [content, embeds, components]
      self
    end
  end

  class FakeChannel
    def initialize(messages) = @messages = messages
    # Mirrors discordrb: a missing message is nil, not an exception.
    def load_message(id) = @messages[id]
  end

  class FakeBot
    attr_reader :sent

    def initialize
      @sent = []
      @messages = {}
      @next_id = 9000
    end

    def send(_channel_id, body, components: nil, **_opts)
      message = FakeSent.new(@next_id += 1)
      @messages[message.id] = message
      @sent << [body, components]
      message
    end

    def channel(_id) = FakeChannel.new(@messages)
    def forget(id) = @messages.delete(id)
  end

  def setup
    super
    server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    @channel = Channel.create!(name: 'snipes', discord_id: next_discord_id, server: server, purpose: 'snipes')
    @bot = FakeBot.new
  end

  def notice = Snipes::Notice.new(@bot)

  def test_first_post_sends_with_both_buttons_and_remembers_the_id
    result = notice.post!

    assert_equal :posted, result.status
    assert_equal 1, @bot.sent.size
    body, view = @bot.sent.first
    assert_includes body, "Don't snipe me"
    refute_nil view, 'no buttons attached'
    ids = view.to_a.flat_map { |row| row[:components].map { |c| c[:custom_id] } }
    assert_equal %w[snipes_optout snipes_optin], ids
    assert_equal result.message_id, @channel.reload.notice_message_id
  end

  def test_a_second_post_refreshes_the_same_message_instead_of_adding_one
    first = notice.post!

    second = notice.post!

    assert_equal :refreshed, second.status
    assert_equal first.message_id, second.message_id
    assert_equal 1, @bot.sent.size, 'posted a second copy'
    assert_equal 1, @bot.channel(0).load_message(first.message_id).edits.size
  end

  def test_a_deleted_message_is_posted_again
    first = notice.post!
    @bot.forget(first.message_id)

    again = notice.post!

    assert_equal :posted, again.status
    refute_equal first.message_id, again.message_id
    assert_equal again.message_id, @channel.reload.notice_message_id
  end

  def test_the_tick_only_acts_on_a_request_and_clears_it
    assert_nil notice.post_requested!, 'posted without being asked'
    assert_empty @bot.sent

    @channel.update!(notice_requested_at: Time.zone.now)
    result = capture_io { @r = notice.post_requested! }.then { @r }

    assert_equal :posted, result.status
    assert_nil @channel.reload.notice_requested_at, 'the request was not consumed'
  end

  def test_no_snipes_channel_is_a_clear_error
    @channel.update!(purpose: nil)

    err = assert_raises(RuntimeError) { notice.post! }
    assert_includes err.message, 'rake snipes:channel'
  end

  # --- rake snipes:channel -----------------------------------------------------

  def test_assigning_the_purpose_moves_it_and_creates_unknown_channels
    other_id = next_discord_id

    moved = Channel.assign_purpose!('snipes', discord_id: other_id)

    assert_equal 'snipes', moved.purpose
    assert_equal other_id, moved.discord_id
    assert_nil @channel.reload.purpose, 'two channels held the same purpose'
    assert_equal moved, Channel.snipes
  end

  def test_only_known_purposes_are_accepted
    assert_raises(ArgumentError) { Channel.assign_purpose!('karaoke', discord_id: next_discord_id) }
  end
end
