require_relative 'test_helper'

class DispatchReadinessTest < AbidTest
  def setup
    super
    @event = make_event(name: 'Sunday School')
  end

  def readiness
    DispatchReadiness.new(RideBoard.new(@event.reload))
  end

  def keys
    readiness.findings.map(&:key)
  end

  def test_a_clean_board_is_ready
    driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    rider = make_rider(@event, 'caitlin', zone: ZONE_1, driver: driver)
    rider.update!(pickup_address: 'Harker Hall lot')

    assert readiness.ready?
    assert_empty readiness.findings
  end

  def test_no_drivers_blocks
    make_rider(@event, 'caitlin', zone: ZONE_1)

    assert_includes keys, :no_drivers
    refute readiness.ready?
  end

  # Waiting riders are worth saying, but should not stop a coordinator sending
  # what they have already worked out.
  def test_unseated_riders_warn_but_do_not_block
    driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    make_rider(@event, 'seated', zone: ZONE_1, driver: driver).update!(pickup_address: 'x')
    make_rider(@event, 'waiting', zone: ZONE_1)

    assert_includes keys, :unseated
    assert readiness.ready?, 'unseated riders should not block the send'
  end

  def test_a_clash_in_one_car_blocks
    driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    a = make_rider(@event, 'kenzo', zone: ZONE_1, driver: driver)
    b = make_rider(@event, 'ronin', zone: ZONE_1, driver: driver)
    [a, b].each { |r| r.update!(pickup_address: 'x') }
    Clash.add(a.user_id, b.user_id)

    assert_includes keys, :clash
    refute readiness.ready?
  end

  def test_an_over_capacity_car_blocks
    driver = make_driver(@event, 'caleb', seats: 1, zone: ZONE_3)
    2.times { |i| make_rider(@event, "over #{i}", zone: ZONE_3, driver: driver).update!(pickup_address: 'x') }

    assert_includes keys, :over_capacity
    refute readiness.ready?
  end

  # The live bug this check exists for: marking a driver out nils their own
  # driver_ride_id but leaves passengers pointing at them, so the riders sit in
  # a car that is not coming and nobody notices.
  def test_a_driver_marked_out_still_holding_passengers_blocks
    driver = make_driver(@event, 'eugene', seats: 4, zone: ZONE_1)
    make_rider(@event, 'caitlin', zone: ZONE_1, driver: driver).update!(pickup_address: 'x')
    driver.update!(status: 'cancelled', driver_ride_id: nil)

    finding = readiness.findings.find { |f| f.key == :driver_out_with_passengers }

    refute_nil finding, 'orphaned passengers were not detected'
    assert_equal :error, finding.severity
    refute readiness.ready?
  end

  # No zone means no location on the user either, so Ride#address resolves to
  # nothing — a driver cannot collect someone whose address nobody knows.
  def test_a_seated_rider_with_no_pickup_address_blocks
    driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    make_rider(@event, 'nowhere', driver: driver)

    assert_includes keys, :rider_no_pickup
    refute readiness.ready?
  end

  def test_a_rider_on_an_overlapping_other_event_warns
    other = make_event(name: 'Retreat departure', starts: (@event.start_time + 30.minutes))
    driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    rider = make_rider(@event, 'caitlin', zone: ZONE_1, driver: driver)
    rider.update!(pickup_address: 'x')
    other.rides.create!(user: rider.user, role: 'rider', status: 'requested')

    finding = readiness.findings.find { |f| f.key == :double_booked }

    refute_nil finding
    assert_equal :warn, finding.severity
    assert readiness.ready?, 'a double booking should not block'
  end

  # Sunday School and Sunday Service are meant to be different services and
  # plenty of people attend both.
  def test_being_on_a_sibling_slot_the_same_day_is_not_a_double_booking
    sibling = make_event(name: 'Sunday Service', starts: (@event.start_time + 1.hour))
    driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    rider = make_rider(@event, 'caitlin', zone: ZONE_1, driver: driver)
    rider.update!(pickup_address: 'x')
    sibling.rides.create!(user: rider.user, role: 'rider', status: 'requested')

    refute_includes keys, :double_booked
  end

  def test_blocking_and_advisory_are_separated
    driver = make_driver(@event, 'caleb', seats: 1, zone: ZONE_3)
    2.times { |i| make_rider(@event, "over #{i}", zone: ZONE_3, driver: driver).update!(pickup_address: 'x') }
    make_rider(@event, 'waiting', zone: ZONE_3)

    r = readiness
    assert_equal [:over_capacity], r.blocking.map(&:key)
    assert_equal [:unseated], r.advisory.map(&:key)
  end
end
