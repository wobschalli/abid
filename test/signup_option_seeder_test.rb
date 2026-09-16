require_relative 'test_helper'

# The seeder is what turns "make a post, then bind seventeen dropdown entries
# by hand" into one click, so the things that matter are that it picks the
# right events and that running it twice is harmless — it runs both on create
# and from a button.
class SignupOptionSeederTest < AbidTest
  def setup
    super
    @server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    @channel = Channel.create!(name: 'bot', discord_id: next_discord_id, server: @server)
    @sunday = Time.zone.today.next_occurring(:sunday)
  end

  def event_at(hour, minute, name)
    Event.create!(name: name, start_time: Time.zone.local(@sunday.year, @sunday.month, @sunday.day, hour, minute))
  end

  def post_for(date = @sunday)
    SignupPost.create!(channel: @channel, service_date: date, status: 'draft')
  end

  def seed(post) = Signup::OptionSeeder.new(post).call

  def test_fills_one_option_per_event_that_day_in_time_order
    event_at(10, 30, 'Sunday Service')
    event_at(9, 30, 'Sunday School')
    post = post_for

    created = seed(post)

    assert_equal 2, created.size
    assert_equal ['Sunday School', 'Sunday Service'], post.reload.options.map { |o| o.event.name }
    assert_equal ['1️⃣', '2️⃣'], post.options.map(&:emoji_unicode)
  end

  def test_a_seeded_post_needs_nothing_but_a_send_time
    event_at(9, 30, 'Sunday School')
    post = post_for
    seed(post)

    assert post.reload.bound?, 'every option should already know its ride'
    assert post.ready_to_send?
  end

  def test_seeding_twice_adds_nothing_and_does_not_collide
    event_at(9, 30, 'Sunday School')
    event_at(10, 30, 'Sunday Service')
    post = post_for
    seed(post)

    # signup_options is uniquely indexed on [signup_post_id, emoji_key], so a
    # naive second pass would raise rather than no-op.
    assert_empty seed(post)
    assert_equal 2, post.reload.options.count
  end

  def test_seeding_works_around_an_emoji_already_in_use
    event_at(9, 30, 'Sunday School')
    post = post_for
    post.options.create!(Signup::EmojiKey.parse('1️⃣').merge(position: 0))

    created = seed(post)

    assert_equal 1, created.size
    refute_equal '1️⃣', created.first.emoji_unicode, 'must not reuse an emoji already on the post'
    assert_equal 2, post.reload.options.count
  end

  def test_ignores_events_on_other_days_and_disabled_ones
    event_at(9, 30, 'Sunday School')
    Event.create!(name: 'Friday Bible Study', start_time: (@sunday - 2).to_time + 18.hours)
    Event.create!(name: 'Cancelled', disabled: true,
                  start_time: Time.zone.local(@sunday.year, @sunday.month, @sunday.day, 14, 0))

    seed(post = post_for)

    assert_equal ['Sunday School'], post.reload.options.map { |o| o.event.name }
  end

  def test_does_nothing_without_a_date_or_once_sent
    assert_empty seed(SignupPost.create!(channel: @channel, status: 'draft'))

    event_at(9, 30, 'Sunday School')
    sent = SignupPost.create!(channel: @channel, service_date: @sunday, status: 'posted',
                              discord_message_id: next_discord_id)
    assert_empty seed(sent), 'a sent post must not grow new options'
  end
end
