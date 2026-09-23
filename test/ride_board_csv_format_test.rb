require_relative 'test_helper'
require 'csv'

# The sheet the coordinator prints and hands round. It has always been kept by
# hand in one shape — drivers as columns, riders stacked underneath, a header
# spanning each service — and the export has to match it, because it gets
# pasted straight back into the same spreadsheet.
class RideBoardCsvFormatTest < AbidTest
  def setup
    super
    sunday = Time.zone.today.next_occurring(:sunday)
    @early = build_service('Sunday School', sunday, 9, 30)
    @late  = build_service('Sunday Service', sunday, 10, 30)
  end

  def build_service(name, date, hour, minute)
    Event.create!(name: name, start_time: Time.zone.local(date.year, date.month, date.day, hour, minute))
  end

  def seat(event, driver_name, rider_names)
    driver = make_driver(event, driver_name, seats: 4)
    rider_names.each do |rider|
      r = make_rider(event, rider)
      r.update!(driver_ride: driver)
    end
    driver
  end

  def csv(event) = CSV.parse(RideBoardCsv.new(RideBoard.new(event)).to_csv)

  def test_the_sheet_covers_the_whole_day_not_one_service
    seat(@early, 'ian', %w[caitlin jalen])
    seat(@late, 'eugene', %w[andrew])

    rows = csv(@early)

    assert_equal [nil, 'Sunday School 9:30 AM', 'Sunday Service 10:30 AM'], rows[0]
    assert_equal %w[Driver ian eugene], rows[1]
  end

  # Exporting from either board gives the same sheet — it is the day's sheet.
  def test_either_board_exports_the_same_day
    seat(@early, 'ian', %w[caitlin])
    seat(@late, 'eugene', %w[andrew])

    assert_equal csv(@early), csv(@late)
  end

  # Drivers are alphabetical, which is stable across exports — the hand-kept
  # sheet ordered them by whim, and a diffable export is worth more.
  def test_riders_stack_under_their_driver
    seat(@early, 'ian', %w[caitlin jalen kenzo])
    seat(@early, 'caleb', %w[kylan])

    rows = csv(@early)
    assert_equal %w[Driver caleb ian], rows[1]

    riders = rows.drop(3).take(3)
    assert_equal ['Riders', 'kylan', 'caitlin'], riders[0]
    assert_equal [nil, nil, 'jalen'], riders[1], 'a shorter column is padded so the grid stays square'
    assert_equal [nil, nil, 'kenzo'], riders[2]
  end

  # The header sits over the first of its drivers; the rest are blank, which is
  # what a merged cell looks like flattened.
  def test_a_service_header_spans_its_drivers
    seat(@early, 'ian', %w[caitlin])
    seat(@early, 'caleb', %w[kylan])
    seat(@late, 'eugene', %w[andrew])

    assert_equal [nil, 'Sunday School 9:30 AM', nil, 'Sunday Service 10:30 AM'], csv(@early)[0]
  end

  def test_the_total_row_counts_riders_per_service
    seat(@early, 'ian', %w[caitlin jalen])
    seat(@early, 'caleb', %w[kylan])
    seat(@late, 'eugene', %w[andrew])

    total = csv(@early).find { |r| r.first == 'Van Total' }

    assert_equal ['Van Total', '3', nil, '1'], total
  end

  def test_anyone_still_unseated_is_listed_rather_than_dropped
    seat(@early, 'ian', %w[caitlin])
    make_rider(@early, 'forgotten')

    rows = csv(@early)

    assert rows.any? { |r| r.first == 'Still waiting' }
    assert rows.any? { |r| r.include?('forgotten') }
  end

  def test_a_day_with_no_drivers_still_produces_a_sheet
    rows = csv(@early)

    assert_equal 'Driver', rows[1].first
    refute_nil rows[0][1]
  end

  def test_the_waiting_block_is_omitted_when_everyone_is_seated
    seat(@early, 'ian', %w[caitlin])

    refute_includes RideBoardCsv.new(RideBoard.new(@early)).to_csv, 'Still waiting'
  end

  # The old sheet carried a zone row and a "1/4" capacity row per car. Neither
  # is in the format this replaces, and the per-service Van Total is the number
  # that actually gets checked.
  def test_the_old_per_car_capacity_row_is_gone
    seat(@early, 'ian', %w[caitlin])

    refute_includes RideBoardCsv.new(RideBoard.new(@early)).to_csv, '1/4'
  end

end
