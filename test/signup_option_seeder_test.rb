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

  # A row that books nothing cannot be reacted to usefully, so it goes and its
  # emoji comes back into circulation for the times that do exist.
  def test_an_option_attached_to_no_ride_is_removed
    event_at(9, 30, 'Sunday School')
    post = post_for
    post.options.create!(Signup::EmojiKey.parse('1️⃣').merge(position: 0))

    created = seed(post)

    assert_equal 1, created.size
    assert_equal 1, post.reload.options.count, 'the orphan row survived'
    assert_equal '1️⃣', post.options.first.emoji_unicode
    assert_equal 'Sunday School', post.options.first.event.name
  end

  # Two rows for the same time means the message offers two emoji for one ride.
  # Real data got into this state, and nothing could get it out again — every
  # row pointed at a live time, so pruning orphans left them all standing.
  def test_a_time_with_two_rows_keeps_only_the_first
    event = event_at(9, 30, 'Sunday School')
    post = post_for
    keep = post.options.create!(Signup::EmojiKey.parse('🙋').merge(event: event, position: 0, label: 'mine'))
    dupe = post.options.create!(Signup::EmojiKey.parse('1️⃣').merge(event: event, position: 1))

    seed(post)

    assert_equal [keep.id], post.reload.options.map(&:id), 'the duplicate row survived'
    # The survivor is the one somebody chose, not the one the machine added.
    assert_equal 'mine', post.options.first.label
    refute SignupOption.exists?(dupe.id)
  end

  # The rule is one row per time, which only holds if cancelling a time takes
  # its row with it. Without this the emoji stayed on the message, collecting
  # sign-ups for a ride that was not happening.
  def test_a_cancelled_time_loses_its_row
    early = event_at(9, 30, 'Sunday School')
    event_at(10, 30, 'Sunday Service')
    seed(post = post_for)
    assert_equal 2, post.reload.options.count

    early.update!(disabled: true)
    seed(post)

    assert_equal ['Sunday Service'], post.reload.options.map { |o| o.event.name }
  end

  # And a time added to the date afterwards gains one.
  def test_a_time_added_later_gains_a_row
    event_at(9, 30, 'Sunday School')
    seed(post = post_for)

    event_at(10, 30, 'Sunday Service')
    seed(post)

    assert_equal ['Sunday School', 'Sunday Service'], post.reload.options.map { |o| o.event.name }
  end

  # Never on a post that has gone out: its emoji are live on a Discord message
  # with reactions attached to them.
  def test_a_posted_signup_is_left_alone
    early = event_at(9, 30, 'Sunday School')
    seed(post = post_for)
    post.update!(status: 'posted', discord_message_id: next_discord_id, posted_at: Time.zone.now)

    early.update!(disabled: true)
    seed(post)

    assert_equal 1, post.reload.options.count, 'pulled a row out from under a live message'
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
