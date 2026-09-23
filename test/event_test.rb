require_relative 'test_helper'

class EventTest < AbidTest
  # A ride is over when its day is. The old rule guessed an end two hours after
  # the start whenever none was recorded, which made a 7am–5pm retreat "past" at
  # 9am — PAST pill up and no way to dispatch, on the morning of the retreat.

  def test_an_event_earlier_today_is_not_past
    this_morning = Event.create!(name: 'Sunday School', start_time: Time.zone.now.beginning_of_day + 8.hours)

    refute_includes Event.past, this_morning
    refute this_morning.past?
    assert_includes Event.upcoming, this_morning
  end

  # The case that prompted this: no end time, and still running long.
  def test_an_all_day_event_with_no_end_time_stays_open_all_day
    retreat = Event.create!(name: 'Fall Retreat', start_time: Time.zone.now.beginning_of_day + 7.hours)

    travel_to(Time.zone.now.beginning_of_day + 15.hours) do
      refute retreat.past?, 'went past while people were still being collected'
      refute_includes Event.past, retreat
    end
  end

  def test_yesterdays_event_is_past
    yesterday = Event.create!(name: 'Last night', start_time: 1.day.ago)

    assert_includes Event.past, yesterday
    assert yesterday.past?
    refute_includes Event.upcoming, yesterday
  end

  # An end time still counts when it is there, so something spanning two days
  # stays live until the second one is over.
  def test_an_event_running_into_another_day_is_not_past_until_that_day_ends
    overnight = Event.create!(name: 'Lock-in', start_time: 1.day.ago, end_time: Time.zone.now + 2.hours)

    refute_includes Event.past, overnight
    refute overnight.past?
  end

  # Ruby and SQL must agree, or the list and the detail page disagree.
  def test_past_in_ruby_matches_past_in_sql
    [
      Event.create!(name: 'a', start_time: 3.hours.ago),
      Event.create!(name: 'b', start_time: 2.days.ago),
      Event.create!(name: 'c', start_time: 3.days.ago, end_time: 2.days.ago),
      Event.create!(name: 'd', start_time: 1.day.from_now),
      Event.create!(name: 'e', start_time: 2.days.ago, end_time: 1.hour.from_now)
    ].each do |event|
      in_sql = Event.past.exists?(event.id)
      assert_equal in_sql, event.past?, "#{event.name} disagrees: SQL=#{in_sql} ruby=#{event.past?}"
    end
  end

  # Nothing may fall between the two — the series page lists upcoming and past
  # side by side, and an event in neither would simply vanish from it.
  def test_every_event_is_either_upcoming_or_past
    [3.hours.ago, 2.days.ago, 1.day.from_now, Time.zone.now].each do |at|
      event = Event.create!(name: "at #{at}", start_time: at)

      assert_equal 1, [Event.past.exists?(event.id), Event.upcoming.exists?(event.id)].count(true),
                   "#{event.name} is in both lists or neither"
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
