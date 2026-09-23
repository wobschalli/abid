require_relative 'test_helper'

# This is the thing that removes the weekly workload, so what matters is that
# it is safe to run on a timer: it must not create a second post for a date, it
# must not touch anything a human has worked on, and it must never back-date a
# send into a 271-person server.
class SignupAutoScheduleTest < AbidTest
  def setup
    super
    @server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    @channel = Channel.create!(name: 'bot', discord_id: next_discord_id, server: @server)
    @sunday = Time.zone.today.next_occurring(:sunday)
    @sunday = @sunday.next_occurring(:sunday) if @sunday < Time.zone.today + 4
  end

  def series(name: 'Sunday Service', at: '09:30', lead: 3, **attrs)
    EventSeries.create!(
      { name: name, weekday: 0, start_time_of_day: at, channel: @channel,
        signup_lead_days: lead, signup_post_time: '20:00' }.merge(attrs)
    )
  end

  def occurrence(series, date = @sunday) = series.ensure_occurrence(date)

  def run_it(**opts) = Signup::AutoSchedule.new(**opts).call

  def test_creates_a_scheduled_post_for_an_uncovered_date
    early = series(name: 'Sunday School', at: '09:30')
    late  = series(name: 'Sunday Service', at: '10:30', section: 'late')
    occurrence(early)
    occurrence(late)

    created = run_it

    assert_equal 1, created.size, 'one post per date, not one per event'
    post = created.first.post
    assert_equal @sunday, post.service_date
    assert_equal 'scheduled', post.reload.status
    assert_equal 2, post.options.count, 'both of that day\'s rides should be on it'
    assert_equal ['Sunday School', 'Sunday Service'], post.options.map { |o| o.event.name }
  end

  # A series with no channel falls back to "the only channel". The snipes
  # channel is a second row in the same table, and must neither be that
  # fallback nor stop the real one from being found.
  def test_the_snipes_channel_is_not_counted_as_a_place_for_rides
    Channel.create!(name: 'snipes', discord_id: next_discord_id, server: @server, purpose: 'snipes')
    occurrence(series(channel: nil))

    post = run_it.first.post

    assert_equal @channel, post.channel
  end

  def test_the_send_time_comes_from_the_series
    s = series(lead: 3)
    occurrence(s)

    post = run_it.first.post

    expected = s.signup_post_at(@sunday)
    assert_equal expected, post.reload.post_at
    assert_equal @sunday - 3, post.post_at.to_date, 'three days before'
    assert_equal 20, post.post_at.hour
  end

  def test_running_twice_creates_nothing_the_second_time
    occurrence(series)
    assert_equal 1, run_it.size

    assert_empty run_it, 'a timer runs this repeatedly; it must be idempotent'
    assert_equal 1, SignupPost.where(service_date: @sunday).count
  end

  def test_a_post_someone_already_made_is_left_alone
    occurrence(series)
    author = User.create!(name: 'Coord', username: "c#{next_discord_id}",
                          discord_id: next_discord_id, password: 'x' * 10)
    mine = SignupPost.create!(channel: @channel, service_date: @sunday, status: 'draft',
                              intro: 'hand-written', created_by: author)

    assert_empty run_it
    assert_equal 'draft', mine.reload.status, "scheduled a human's draft out from under them"
    assert_equal 'hand-written', mine.intro
    assert_equal 1, SignupPost.where(service_date: @sunday).count
  end

  # --- rescuing automation's own abandoned drafts ---------------------------
  #
  # A post created for a date that had no events yet was left as a draft, and
  # nothing ever re-attempted schedule! when the events appeared. The
  # discriminator is created_by: nil is automation's own work and fair game;
  # a user id is a human mid-edit and untouchable. An earlier rescue without
  # that distinction was removed for scheduling someone's half-written post.

  def test_an_abandoned_automation_draft_is_scheduled
    s = series
    occurrence(s)
    orphan = SignupPost.create!(channel: @channel, service_date: @sunday, status: 'draft',
                                post_at: s.signup_post_at(@sunday))
    Signup::OptionSeeder.new(orphan).call

    results = run_it

    assert_equal 'scheduled', orphan.reload.status, 'left a ready automation draft to rot'
    assert results.any? { |r| r.post.id == orphan.id && r.scheduled }
    assert_equal 1, SignupPost.where(service_date: @sunday).count, 'made a second post instead'
  end

  def test_a_rescued_draft_gets_options_and_a_send_time_derived
    s = series
    occurrence(s)
    bare = SignupPost.create!(channel: @channel, service_date: @sunday, status: 'draft')
    assert_empty bare.options
    assert_nil bare.post_at

    run_it

    bare.reload
    assert_equal 'scheduled', bare.status
    assert_equal s.signup_post_at(@sunday), bare.post_at
    assert bare.options.any?, 'scheduled with nothing to react to'
  end

  # Back-dating a send into the server is still forbidden, rescue or not.
  def test_an_automation_draft_whose_time_has_passed_stays_a_draft
    s = series(lead: 0)
    today = Time.zone.today
    s.ensure_occurrence(today)
    stale = SignupPost.create!(channel: @channel, service_date: today, status: 'draft',
                               post_at: 1.hour.ago)
    Signup::OptionSeeder.new(stale).call

    run_it

    assert_equal 'draft', stale.reload.status
  end

  # A series added days before its first occurrence computes a send time that
  # has already passed. Sending that on the next tick would fire a message into
  # the channel with no warning.
  def test_a_send_time_in_the_past_leaves_a_draft
    s = series(lead: 30)
    occurrence(s)

    result = run_it.first

    refute result.scheduled
    assert_equal 'draft', result.post.reload.status
    refute_includes SignupPost.due, result.post
  end

  def test_disabled_events_do_not_get_a_post
    s = series
    occurrence(s).update!(disabled: true)

    assert_empty run_it
  end

  def test_a_date_beyond_the_horizon_is_left_for_later
    s = series
    far = @sunday + 10.weeks
    occurrence(s, far)

    assert_empty run_it(horizon_weeks: 3).select { |r| r.post.service_date == far }
  end

  def test_it_carries_the_series_footer_onto_the_post
    s = series(signup_outro: 'React by 8am Sunday')
    occurrence(s)

    assert_equal 'React by 8am Sunday', run_it.first.post.outro
  end
  # --- setting one date up early, from the calendar ------------------------

  def test_ensure_for_creates_seeds_and_schedules_a_single_date
    s = series
    occurrence(s)

    post = Signup::AutoSchedule.new.ensure_for(@sunday)

    assert_equal 'scheduled', post.status
    assert_equal s.signup_post_at(@sunday), post.post_at
    assert post.options.any?, 'no emoji rows to react to'
  end

  # Clicking the same day twice must not make a second post.
  def test_ensure_for_is_idempotent
    occurrence(series)

    first = Signup::AutoSchedule.new.ensure_for(@sunday)
    second = Signup::AutoSchedule.new.ensure_for(@sunday)

    assert_equal first.id, second.id
    assert_equal 1, SignupPost.where(service_date: @sunday).count
  end

  # And it hands back a draft somebody is already writing rather than
  # scheduling it out from under them.
  def test_ensure_for_returns_an_existing_draft_untouched
    occurrence(series)
    mine = SignupPost.create!(channel: @channel, service_date: @sunday,
                              status: 'draft', intro: 'hand-written')

    assert_equal mine.id, Signup::AutoSchedule.new.ensure_for(@sunday).id
    assert_equal 'draft', mine.reload.status
    assert_equal 'hand-written', mine.intro
  end

  def test_ensure_for_does_nothing_for_a_date_with_no_events
    assert_nil Signup::AutoSchedule.new.ensure_for(@sunday)
  end

  # Reaches past the three-week automation window on purpose — that is the
  # whole point of setting a date up by hand.
  def test_ensure_for_reaches_beyond_the_automatic_horizon
    s = series
    far = @sunday + 12.weeks
    s.ensure_occurrence(far)

    assert_nil run_it.find { |r| r.post.service_date == far }, 'automation should not reach that far'
    refute_nil Signup::AutoSchedule.new.ensure_for(far)
  end

end
