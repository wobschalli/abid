require_relative 'test_helper'
require 'csv'

class RideBoardCsvTest < AbidTest
  def test_one_column_per_car_with_riders_beneath
    event = make_event
    ian = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    make_driver(event, 'caleb', seats: 3, zone: ZONE_3)
    make_rider(event, 'caitlin', zone: ZONE_1, driver: ian)

    rows = CSV.parse(RideBoardCsv.new(RideBoard.new(event)).to_csv)

    assert_equal %w[caleb ian], rows[0].sort
    ian_column = rows[0].index('ian')
    assert_equal 'caitlin', rows[2][ian_column]
    assert_equal '1/4', rows.find { |r| r.include?('1/4') }[ian_column]
  end

  def test_lists_people_still_waiting
    event = make_event
    make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    make_rider(event, 'stranded', zone: ZONE_5)

    csv = RideBoardCsv.new(RideBoard.new(event)).to_csv

    assert_includes csv, 'Still waiting'
    assert_includes csv, 'stranded'
  end

  def test_handles_an_event_with_no_drivers
    event = make_event
    make_rider(event, 'stranded', zone: ZONE_5)

    csv = RideBoardCsv.new(RideBoard.new(event)).to_csv

    assert_includes csv, 'No drivers assigned'
    assert_includes csv, 'stranded'
  end

  def test_omits_the_waiting_block_when_everyone_is_seated
    event = make_event
    ian = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    make_rider(event, 'caitlin', zone: ZONE_1, driver: ian)

    refute_includes RideBoardCsv.new(RideBoard.new(event)).to_csv, 'Still waiting'
  end
end
