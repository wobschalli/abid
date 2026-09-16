require_relative 'test_helper'

class EventTest < AbidTest
  # Discord-created events frequently have no end_time. Before the coalesce they
  # never appeared under Past, which made the browser untrustworthy.
  def test_past_includes_events_with_no_end_time
    stale = Event.create!(name: 'No end', start_time: 4.hours.ago)

    assert_includes Event.past, stale
    assert stale.past?
  end

  def test_an_event_that_started_recently_is_not_past_yet
    fresh = Event.create!(name: 'Just started', start_time: 30.minutes.ago)

    refute_includes Event.past, fresh
    refute fresh.past?
  end

  def test_past_respects_an_explicit_end_time
    long = Event.create!(name: 'Long', start_time: 5.hours.ago, end_time: 1.hour.from_now)

    refute_includes Event.past, long
  end

  # Ruby and SQL must agree, or the index and the detail page disagree.
  def test_end_time_or_estimate_matches_the_past_scope
    [
      Event.create!(name: 'a', start_time: 3.hours.ago),
      Event.create!(name: 'b', start_time: 1.hour.ago),
      Event.create!(name: 'c', start_time: 3.hours.ago, end_time: 2.hours.ago),
      Event.create!(name: 'd', start_time: 1.hour.from_now)
    ].each do |event|
      in_sql = Event.past.exists?(event.id)
      assert_equal in_sql, event.past?, "#{event.name} disagrees: SQL=#{in_sql} ruby=#{event.past?}"
    end
  end

  def test_recurring_and_one_off
    series = EventSeries.create!(name: 'S', weekday: 0, start_time_of_day: Time.zone.parse('09:30'))
    occurrence = series.ensure_occurrence(Time.zone.today + 7)
    one_off = Event.create!(name: 'Retreat', start_time: 1.week.from_now)

    assert occurrence.recurring?
    refute occurrence.one_off?
    assert one_off.one_off?
    refute one_off.recurring?
    assert_includes Event.recurring, occurrence
    assert_includes Event.one_off, one_off
  end

  # The poller's scopes and their tests lived here. They belonged to the legacy
  # rides-message path, deleted in 2900_drop_legacy_rides_message — a second
  # mechanism that posted alongside the sign-up publisher and had been raising
  # NoMethodError on every send since `Event has_many :emojis` was dropped.

  private

  def demo_server
    @demo_server ||= Server.create!(name: "Test #{next_discord_id}", discord_id: next_discord_id)
  end
end
