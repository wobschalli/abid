require_relative 'test_helper'

class AcademicBreakTest < AbidTest
  def sunday_series(**overrides)
    EventSeries.create!({
      name: 'Sunday Service',
      weekday: 0,
      start_time_of_day: Time.zone.parse('09:30'),
      interval_weeks: 1,
      horizon_weeks: 6
    }.merge(overrides))
  end

  def next_sunday
    @next_sunday ||= begin
      today = Time.zone.today
      offset = (0 - today.wday) % 7
      today + (offset.zero? ? 7 : offset)
    end
  end

  def make_break(name, from, to)
    AcademicBreak.create!(name: name, starts_on: from, ends_on: to)
  end

  # --- validation -----------------------------------------------------------

  def test_end_must_not_precede_start
    academic_break = AcademicBreak.new(name: 'Backwards',
                                       starts_on: Time.zone.today,
                                       ends_on: Time.zone.today - 1)

    refute academic_break.valid?
    assert_includes academic_break.errors[:ends_on].to_sentence, 'before'
  end

  def test_a_single_day_break_is_fine
    assert AcademicBreak.new(name: 'Reading day', starts_on: Time.zone.today,
                             ends_on: Time.zone.today).valid?
  end

  def test_days_counts_inclusively
    academic_break = make_break('Week', next_sunday, next_sunday + 6)

    assert_equal 7, academic_break.days
  end

  # --- skipping occurrences -------------------------------------------------

  def test_dates_inside_a_break_are_skipped
    series = sunday_series
    skipped = next_sunday + 7
    make_break('Spring break', skipped - 2, skipped + 2)

    dates = series.occurrence_dates(from: next_sunday, to: next_sunday + 21)

    refute_includes dates, skipped
    assert_includes dates, next_sunday
    assert_includes dates, next_sunday + 14
  end

  # The cadence keeps counting through the gap rather than sliding — a weekly
  # service resumes on its own weekday, not a week late.
  def test_the_cadence_is_not_shifted_by_a_break
    series = sunday_series
    make_break('Winter break', next_sunday + 5, next_sunday + 16)

    dates = series.occurrence_dates(from: next_sunday, to: next_sunday + 28)

    assert_equal [next_sunday, next_sunday + 21, next_sunday + 28], dates
    dates.each { |d| assert_equal 0, d.wday }
  end

  def test_a_long_break_can_remove_every_occurrence
    series = sunday_series
    make_break('Summer', next_sunday - 7, next_sunday + 60)

    assert_empty series.occurrence_dates(from: next_sunday, to: next_sunday + 28)
  end

  def test_breaks_can_be_ignored_explicitly
    series = sunday_series
    make_break('Spring break', next_sunday - 1, next_sunday + 1)

    assert_empty series.occurrence_dates(from: next_sunday, to: next_sunday + 3)
    refute_empty series.occurrence_dates(from: next_sunday, to: next_sunday + 3, skip_breaks: false)
  end

  def test_generation_creates_nothing_inside_a_break
    series = sunday_series
    make_break('Spring break', next_sunday - 1, next_sunday + 1)

    series.generate_upcoming(from: next_sunday, weeks: 0)

    assert_equal 0, series.events.where(occurrence_date: next_sunday).count
  end

  # --- retroactively adding a break ----------------------------------------

  def test_adding_a_break_disables_occurrences_already_generated
    series = sunday_series
    event = series.ensure_occurrence(next_sunday)
    refute event.disabled

    make_break('Late notice', next_sunday - 1, next_sunday + 1).disable_future_occurrences!

    assert event.reload.disabled
  end

  # Disabling, not destroying: a destroy takes the roster with it.
  def test_disabling_keeps_the_roster
    series = sunday_series
    event = series.ensure_occurrence(next_sunday)
    rider = make_rider(event, 'caitlin', zone: ZONE_1)

    make_break('Late notice', next_sunday - 1, next_sunday + 1).disable_future_occurrences!

    assert Ride.exists?(rider.id), 'the roster was destroyed'
    assert Event.exists?(event.id)
  end

  def test_past_occurrences_are_never_touched
    series = sunday_series
    past = series.ensure_occurrence(Time.zone.today - 14)
    refute past.disabled

    make_break('Retrospective', Time.zone.today - 21, Time.zone.today - 7).disable_future_occurrences!

    refute past.reload.disabled, 'history was rewritten'
  end

  # --- lookup helpers -------------------------------------------------------

  def test_covering_finds_the_right_break
    make_break('Spring break', next_sunday, next_sunday + 6)

    assert_equal 1, AcademicBreak.covering(next_sunday + 3).count
    assert_equal 0, AcademicBreak.covering(next_sunday + 10).count
  end

  def test_ranges_are_bounded_by_the_window
    make_break('Far future', next_sunday + 300, next_sunday + 310)
    make_break('Soon', next_sunday, next_sunday + 2)

    ranges = AcademicBreak.ranges(from: next_sunday, to: next_sunday + 30)

    assert_equal 1, ranges.size
  end
end
