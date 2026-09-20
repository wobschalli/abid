require_relative 'test_helper'

# The two promises the optimizer makes are worth more than its optimality:
# seated riders never change cars, and the pool is droppable rather than the
# solve being fragile. Optimality is asserted only loosely (the obviously
# cheaper car wins) because the exact objective is the solver's business.
#
# Every test injects a fake matrix, so no HTTP and no dependence on real
# geography — distances here are whatever the test says they are.
class RidesOptimizerTest < AbidTest
  # Seconds come from a hash keyed on location ids; unknown pairs are far.
  class FakeMatrix < Rides::TravelMatrix
    def initialize(times)
      super(api_key: nil)
      @times = times
    end

    def warm(_points); end

    def seconds(a, b)
      return 0 if a.nil? || b.nil? || a.location_id == b.location_id

      @times.fetch([a.location_id, b.location_id], 9_999)
    end
  end

  def setup
    super
    @venue = Location.create!(name: 'venue', zone: ZONE_1, lat: 40.45, lon: -86.97)
    @near = Location.create!(name: 'near', zone: ZONE_1, lat: 40.43, lon: -86.91)
    @far = Location.create!(name: 'far', zone: ZONE_2, lat: 40.42, lon: -86.90)
    @event = make_event(name: 'Sunday Service')
    @event.update!(location: @venue)
  end

  def driver_at(name, location, seats: 4)
    ride = make_driver(@event, name, seats: seats, zone: location.zone)
    ride.update!(pickup_location: location)
    ride
  end

  def rider_at(name, location, driver: nil)
    ride = make_rider(@event, name, zone: location.zone, driver: driver)
    ride.update!(pickup_location: location)
    ride
  end

  def optimize(times)
    Rides::Optimizer.call(RideBoard.new(@event.reload), matrix: FakeMatrix.new(times))
  end

  # Symmetric convenience: same time both directions unless overridden.
  def matrix(pairs)
    pairs.flat_map { |(a, b), s| [[[a.id, b.id], s], [[b.id, a.id], s]] }.to_h
  end

  def test_seats_the_pool_into_the_cheaper_car
    near_driver = driver_at('ian', @near)
    far_driver = driver_at('caleb', @far)
    rider = rider_at('caitlin', @near)

    result = optimize(matrix(
      [@near, @venue] => 600, [@far, @venue] => 700,
      [@near, @far] => 1200, [@near, @near] => 0
    ))

    assert_equal :or_tools, result.engine
    assert_equal 1, result.seated
    assert_equal near_driver.id, rider.reload.driver_ride_id,
                 'the rider at the near driver\'s own stop went to the far car'
    refute_equal far_driver.id, rider.reload.driver_ride_id
  end

  # The core promise: a seated rider stays put even when moving them is
  # obviously cheaper. Construct the temptation explicitly.
  def test_a_seated_rider_never_changes_cars
    expensive = driver_at('ian', @far)
    driver_at('caleb', @near)
    stuck = rider_at('caitlin', @near, driver: expensive)

    optimize(matrix(
      [@near, @venue] => 60, [@far, @venue] => 60, [@near, @far] => 3600
    ))

    assert_equal expensive.id, stuck.reload.driver_ride_id,
                 'the optimizer moved a seated rider to save time — forbidden'
  end

  def test_a_late_rider_joins_without_disturbing_anyone
    car_a = driver_at('ian', @near, seats: 2)
    car_b = driver_at('caleb', @far, seats: 2)
    veteran_a = rider_at('anna', @near, driver: car_a)
    veteran_b = rider_at('brian', @far, driver: car_b)
    late = rider_at('priya', @near)

    result = optimize(matrix(
      [@near, @venue] => 300, [@far, @venue] => 300, [@near, @far] => 2000
    ))

    assert_equal 1, result.seated
    assert_equal car_a.id, late.reload.driver_ride_id, 'joined the wrong car'
    assert_equal car_a.id, veteran_a.reload.driver_ride_id
    assert_equal car_b.id, veteran_b.reload.driver_ride_id
  end

  def test_capacity_is_respected_and_overflow_stays_in_the_pool
    driver_at('ian', @near, seats: 1)
    riders = 3.times.map { |i| rider_at("r#{i}", @near) }

    result = optimize(matrix([@near, @venue] => 300))

    seated = riders.count { |r| r.reload.driver_ride_id.present? }
    assert_equal 1, seated, 'a one-seat car took more than one rider'
    assert_equal 2, result.dropped
    assert_equal 2, RideBoard.new(@event.reload).pool.size, 'overflow vanished instead of staying visible'
  end

  # Pressing the button twice must not shuffle anything: no new riders and no
  # real improvement means no writes.
  def test_running_twice_is_a_noop
    driver_at('ian', @near, seats: 4)
    rider_at('caitlin', @near)
    times = matrix([@near, @venue] => 300)

    optimize(times)
    stamps = @event.reload.rides.order(:id).pluck(:updated_at, :pickup_position, :driver_ride_id)

    result = optimize(times)

    assert_equal 0, result.seated
    assert_equal 0, result.reordered
    assert_equal stamps, @event.reload.rides.order(:id).pluck(:updated_at, :pickup_position, :driver_ride_id),
                 'a no-op run still wrote to rides'
  end

  # A rider whose location has no coordinates still has a zone, and the zone's
  # centroid keeps them optimizable rather than invisible.
  def test_a_coordless_rider_is_still_seated
    driver_at('ian', @near, seats: 4)
    homeless = make_rider(@event, 'mystery', zone: ZONE_1)
    refute homeless.pickup&.coords?, 'fixture drift: this rider was supposed to be unlocatable'

    result = Rides::Optimizer.call(RideBoard.new(@event.reload))

    assert_operator result.seated, :>=, 1
    refute_nil homeless.reload.driver_ride_id, 'a coordless rider was left invisible in the pool'
  end

  # No venue coordinates → the solver cannot run → the greedy filler answers.
  # The button must degrade, never 500.
  def test_falls_back_to_greedy_when_the_venue_is_unlocatable
    @venue.update_columns(lat: nil, lon: nil)
    driver_at('ian', @near, seats: 4)
    rider = rider_at('caitlin', @near)

    result = capture_io { @r = optimize(matrix({})) }.then { @r }

    assert_equal :greedy, result.engine
    refute_nil rider.reload.driver_ride_id, 'the fallback did not seat anyone either'
  end

  # Inserting into a sent car flips exactly that driver to changed — the
  # digest is a set, so the untouched car stays sent.
  def test_late_insert_flips_only_the_affected_driver
    car_a = driver_at('ian', @near, seats: 3)
    car_b = driver_at('caleb', @far, seats: 3)
    rider_at('anna', @near, driver: car_a)
    rider_at('brian', @far, driver: car_b)

    board = RideBoard.new(@event.reload)
    dispatch = DispatchPlanner.new(board, scope: 'all').call
    dispatch.messages.update_all(status: 'sent', sent_at: Time.zone.now)

    rider_at('priya', @near)
    optimize(matrix(
      [@near, @venue] => 300, [@far, @venue] => 300, [@near, @far] => 2000
    ))

    status = DispatchStatus.new(RideBoard.new(@event.reload))
    assert_equal :changed, status.state_for(car_a), 'the driver gaining a rider must be re-sendable'
    assert_equal :sent, status.state_for(car_b), 'an untouched car was re-flagged'
  end
end
