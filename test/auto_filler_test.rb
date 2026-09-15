require_relative 'test_helper'

class AutoFillerTest < AbidTest
  def test_seats_waiting_riders
    event = make_event
    driver = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    riders = 3.times.map { |i| make_rider(event, "rider #{i}", zone: ZONE_1) }

    seated = AutoFiller.new(event).call

    assert_equal 3, seated
    riders.each { |r| assert_equal driver.id, r.reload.driver_ride_id }
    assert_equal 'assigned', riders.first.reload.status
  end

  def test_never_exceeds_capacity
    event = make_event
    make_driver(event, 'caleb', seats: 2, zone: ZONE_3)
    4.times { |i| make_rider(event, "rider #{i}", zone: ZONE_3) }

    AutoFiller.new(event).call

    assert_equal 2, event.rides.riders.where.not(driver_ride_id: nil).count
    assert_equal 2, event.rides.unassigned.count
  end

  def test_counts_already_seated_riders_against_capacity
    event = make_event
    driver = make_driver(event, 'tobin', seats: 2, zone: ZONE_5)
    make_rider(event, 'already here', zone: ZONE_5, driver: driver)
    make_rider(event, 'waiting a', zone: ZONE_5)
    make_rider(event, 'waiting b', zone: ZONE_5)

    AutoFiller.new(event).call

    assert_equal 2, driver.passengers.active.count
    assert_equal 1, event.rides.unassigned.count
  end

  def test_does_not_move_a_seated_rider
    event = make_event
    full = make_driver(event, 'christina', seats: 4, zone: ZONE_2)
    _empty = make_driver(event, 'ranbir', seats: 4, zone: ZONE_2)
    seated = make_rider(event, 'dalton', zone: ZONE_2, driver: full)

    AutoFiller.new(event).call

    assert_equal full.id, seated.reload.driver_ride_id
  end

  def test_keeps_clashing_riders_apart
    event = make_event
    a = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    b = make_driver(event, 'caleb', seats: 4, zone: ZONE_1)
    one = make_rider(event, 'kenzo', zone: ZONE_1)
    two = make_rider(event, 'ronin', zone: ZONE_1)
    Clash.add(one.user_id, two.user_id)

    AutoFiller.new(event).call

    refute_nil one.reload.driver_ride_id
    refute_nil two.reload.driver_ride_id
    refute_equal one.reload.driver_ride_id, two.reload.driver_ride_id
    assert_includes [a.id, b.id], one.reload.driver_ride_id
  end

  def test_leaves_rider_waiting_rather_than_breaking_a_clash
    event = make_event
    only = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    seated = make_rider(event, 'kenzo', zone: ZONE_1, driver: only)
    waiting = make_rider(event, 'ronin', zone: ZONE_1)
    Clash.add(seated.user_id, waiting.user_id)

    AutoFiller.new(event).call

    assert_nil waiting.reload.driver_ride_id
  end

  def test_closest_zone_strategy_prefers_matching_zone
    event = make_event
    far = make_driver(event, 'far', seats: 4, zone: ZONE_3)
    near = make_driver(event, 'near', seats: 4, zone: ZONE_5)
    # `far` is emptier only if we ignore zone; both are empty here, so zone decides.
    rider = make_rider(event, 'renata', zone: ZONE_5)

    AutoFiller.new(event, strategy: 'closest').call

    assert_equal near.id, rider.reload.driver_ride_id
    refute_equal far.id, rider.reload.driver_ride_id
  end

  def test_spread_strategy_balances_across_cars
    event = make_event
    busy = make_driver(event, 'busy', seats: 4, zone: ZONE_5)
    quiet = make_driver(event, 'quiet', seats: 4, zone: ZONE_3)
    3.times { |i| make_rider(event, "seated #{i}", zone: ZONE_5, driver: busy) }
    rider = make_rider(event, 'newcomer', zone: ZONE_5)

    AutoFiller.new(event, strategy: 'spread').call

    assert_equal quiet.id, rider.reload.driver_ride_id
  end

  def test_ignores_drivers_who_are_not_driving_today
    event = make_event
    off = make_driver(event, 'eugene', seats: 4, zone: ZONE_1)
    off.update!(status: 'cancelled')
    rider = make_rider(event, 'caitlin', zone: ZONE_1)

    assert_equal 0, AutoFiller.new(event).call
    assert_nil rider.reload.driver_ride_id
  end

  def test_ignores_riders_who_are_not_coming
    event = make_event
    make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    away = make_rider(event, 'gone', zone: ZONE_1, status: 'no_show')

    assert_equal 0, AutoFiller.new(event).call
    assert_nil away.reload.driver_ride_id
  end

  def test_unknown_strategy_falls_back_to_closest
    event = make_event
    make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    rider = make_rider(event, 'caitlin', zone: ZONE_1)

    AutoFiller.new(event, strategy: 'nonsense').call

    refute_nil rider.reload.driver_ride_id
  end
end
