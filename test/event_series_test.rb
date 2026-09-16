require_relative 'test_helper'

class EventSeriesTest < AbidTest
  # US DST in 2026: forward Sun 8 March, back Sun 1 November.
  SPRING_FORWARD = Date.new(2026, 3, 8)
  FALL_BACK = Date.new(2026, 11, 1)

  def series(**overrides)
    EventSeries.create!({
      name: 'Sunday Service',
      section: 'early',
      weekday: 0,
      start_time_of_day: Time.zone.parse('09:30'),
      end_time_of_day: Time.zone.parse('11:00'),
      message: 'React if you need a ride.',
      interval_weeks: 1,
      horizon_weeks: 3
    }.merge(overrides))
  end

  # --- the bug this whole phase exists to prevent --------------------------

  def test_wall_clock_time_survives_spring_forward
    s = series(starts_on: SPRING_FORWARD - 14)
    before = s.ensure_occurrence(SPRING_FORWARD - 7)
    after  = s.ensure_occurrence(SPRING_FORWARD)

    assert_equal '09:30', before.start_time.in_time_zone(s.zone).strftime('%H:%M')
    assert_equal '09:30', after.start_time.in_time_zone(s.zone).strftime('%H:%M')
    # The UTC offset really did change; the wall clock did not.
    refute_equal before.start_time.utc_offset, after.start_time.utc_offset
  end

  def test_wall_clock_time_survives_falling_back
    s = series(starts_on: FALL_BACK - 14)
    before = s.ensure_occurrence(FALL_BACK - 7)
    after  = s.ensure_occurrence(FALL_BACK)

    assert_equal '09:30', before.start_time.in_time_zone(s.zone).strftime('%H:%M')
    assert_equal '09:30', after.start_time.in_time_zone(s.zone).strftime('%H:%M')
    refute_equal before.start_time.utc_offset, after.start_time.utc_offset
  end

  def test_occurrence_dates_step_by_calendar_week_across_dst
    s = series(starts_on: SPRING_FORWARD - 7)
    dates = s.occurrence_dates(from: SPRING_FORWARD - 7, to: SPRING_FORWARD + 7)

    assert_equal [SPRING_FORWARD - 7, SPRING_FORWARD, SPRING_FORWARD + 7], dates
    dates.each { |d| assert_equal 0, d.wday, "#{d} is not a Sunday" }
  end

  # --- idempotency ---------------------------------------------------------

  def test_ensure_occurrence_is_idempotent
    s = series
    date = next_sunday
    first = s.ensure_occurrence(date)
    second = s.ensure_occurrence(date)

    assert_equal first.id, second.id
    assert_equal 1, s.events.where(occurrence_date: date).count
  end

  def test_generate_upcoming_twice_creates_nothing_new
    s = series(horizon_weeks: 3)
    s.generate_upcoming(from: next_sunday)
    count = s.events.count
    s.generate_upcoming(from: next_sunday)

    assert_equal count, s.events.count
  end

  def test_generate_upcoming_respects_the_horizon
    s = series(horizon_weeks: 2)
    created = s.generate_upcoming(from: next_sunday)

    assert_equal 3, created.size # weeks 0, 1 and 2 inclusive
  end

  def test_generate_upcoming_stamps_last_generated_on
    s = series
    created = s.generate_upcoming(from: next_sunday)

    assert_equal created.map(&:occurrence_date).max, s.reload.last_generated_on
  end

  # --- cadence and bounds --------------------------------------------------

  def test_fortnightly_skips_a_week
    s = series(interval_weeks: 2, starts_on: next_sunday)
    dates = s.occurrence_dates(from: next_sunday, to: next_sunday + 28)

    assert_equal [next_sunday, next_sunday + 14, next_sunday + 28], dates
  end

  def test_ends_on_stops_generation
    s = series(starts_on: next_sunday, ends_on: next_sunday + 7)
    dates = s.occurrence_dates(from: next_sunday, to: next_sunday + 28)

    assert_equal [next_sunday, next_sunday + 7], dates
  end

  def test_starts_on_in_the_future_is_respected
    s = series(starts_on: next_sunday + 14)
    dates = s.occurrence_dates(from: next_sunday, to: next_sunday + 28)

    assert_equal [next_sunday + 14, next_sunday + 21, next_sunday + 28], dates
  end

  def test_a_series_without_a_weekday_generates_nothing
    s = series(weekday: nil)

    assert_empty s.occurrence_dates
    assert_nil s.occurrence_for(next_sunday)
    assert_empty s.generate_upcoming
  end

  # --- occurrence contents -------------------------------------------------

  def test_occurrence_copies_the_template
    s = series
    event = s.ensure_occurrence(next_sunday)

    assert_equal 'Sunday Service', event.name
    assert_equal 'early', event.section
    assert_equal next_sunday, event.occurrence_date
    assert_equal s.location, event.location
    assert event.recurring?
    refute event.one_off?
  end

  def test_two_series_can_share_a_date_without_colliding
    early = series(section: 'early', start_time_of_day: Time.zone.parse('09:30'))
    late  = series(section: 'late',  start_time_of_day: Time.zone.parse('10:30'))

    a = early.ensure_occurrence(next_sunday)
    b = late.ensure_occurrence(next_sunday)

    refute_equal a.id, b.id
    assert_equal next_sunday, a.occurrence_date
    assert_equal next_sunday, b.occurrence_date
  end

  # --- generator -----------------------------------------------------------

  def test_generator_covers_every_active_series
    a = series(name: 'Sunday Service')
    b = series(name: 'Friday Study', weekday: 5)
    series(name: 'Retired', disabled: true)

    EventGenerator.call(from: next_sunday)

    assert a.events.any?
    assert b.events.any?
    assert_equal 0, EventSeries.find_by(name: 'Retired').events.count
  end

  def test_generator_can_target_one_series
    a = series(name: 'Only me')
    b = series(name: 'Not me', weekday: 5)

    EventGenerator.call(from: next_sunday, only: a)

    assert a.events.any?
    assert_equal 0, b.events.count
  end

  def test_generator_is_idempotent
    s = series
    EventGenerator.call(from: next_sunday)
    count = s.events.count
    EventGenerator.call(from: next_sunday)

    assert_equal count, s.events.count
  end

  private

  def next_sunday
    @next_sunday ||= begin
      today = Time.zone.today
      today + ((0 - today.wday) % 7 == 0 ? 7 : (0 - today.wday) % 7)
    end
  end
end
