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
    mine = SignupPost.create!(channel: @channel, service_date: @sunday, status: 'draft',
                              intro: 'hand-written')

    assert_empty run_it
    assert_equal 'hand-written', mine.reload.intro
    assert_equal 1, SignupPost.where(service_date: @sunday).count
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
end
