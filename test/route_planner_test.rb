require_relative 'test_helper'

class RoutePlannerTest < AbidTest
  def setup
    super
    @event = make_event(name: 'Sunday School')
    @venue = Location.create!(name: 'Church lot', zone: ZONE_1, lat: 40.4259, lon: -86.9081)
    @event.update!(location: @venue)
    @driver = make_driver(@event, 'ian', seats: 6, zone: ZONE_1)
  end

  def plan
    board = RideBoard.new(@event.reload)
    car = board.cars.first
    RoutePlanner.new(car, event: @event).call
  end

  def seat(name, zone:, address: nil, location: nil)
    ride = make_rider(@event, name, zone: zone, driver: @driver)
    ride.update!(pickup_address: address, pickup_location: location)
    ride
  end

  def test_pickups_come_before_the_destination
    seat('caitlin', zone: ZONE_1, location: location_in(ZONE_1))

    stops = plan.stops
    assert_equal :destination, stops.last.kind
    assert_equal 'Church lot', stops.last.name
  end

  # Same board must give the same order every time, or the dispatch digest flaps
  # and every driver shows as "changed since sent" forever.
  def test_ordering_is_deterministic
    seat('zed', zone: ZONE_3, location: location_in(ZONE_3))
    seat('amy', zone: ZONE_3, location: location_in(ZONE_3))
    seat('bob', zone: ZONE_1, location: location_in(ZONE_1))

    first = plan.pickups.map(&:name)
    second = plan.pickups.map(&:name)

    assert_equal first, second
    # Grouped by zone in Location::ZONES order, then by name within a zone — so
    # a driver collects a whole area at a time. Deliberately expressed in terms
    # of ZONE_1/ZONE_3 rather than place names, so the next zone rename does not
    # touch this test.
    assert_equal %w[bob amy zed], first
  end

  def test_two_riders_at_one_address_are_a_single_stop
    shared = location_in(ZONE_3)
    seat('a', zone: ZONE_3, location: shared)
    seat('b', zone: ZONE_3, location: shared)

    url = plan.maps_url
    assert_nil url[/waypoints=/], 'the same address was added twice'
  end

  # A rider collected from the venue itself must not become the destination.
  def test_a_rider_at_the_venue_does_not_replace_the_destination
    seat('at the church', zone: ZONE_1, location: @venue)
    seat('elsewhere', zone: ZONE_3, location: location_in(ZONE_3))

    url = plan.maps_url
    destination = url[/destination=([^&]*)/, 1]

    assert_equal '40.425900%2C-86.908100', destination
  end

  def test_an_address_with_no_coordinates_still_appears_in_the_link
    seat('freetext', zone: ZONE_3, address: '12 Nowhere Lane')

    url = plan.maps_url
    assert_includes url, CGI.escape('12 Nowhere Lane')
  end

  def test_no_destination_means_no_link
    @event.update!(location: nil)
    seat('caitlin', zone: ZONE_1, location: location_in(ZONE_1))

    assert_nil plan.maps_url
  end

  def test_an_empty_car_produces_no_link
    assert_nil plan.maps_url
  end

  def test_waypoints_are_capped_and_flagged
    (RoutePlanner::MAX_WAYPOINTS + 3).times do |i|
      loc = Location.create!(name: "stop #{i}", zone: ZONE_3, lat: 40.5 + (i / 1000.0), lon: -86.9)
      seat("rider #{i}", zone: ZONE_3, location: loc)
    end

    result = plan
    assert result.truncated, 'over the cap but not flagged'
    waypoints = result.maps_url[/waypoints=([^&]*)/, 1].split('%7C')
    assert_equal RoutePlanner::MAX_WAYPOINTS, waypoints.size
  end
end
