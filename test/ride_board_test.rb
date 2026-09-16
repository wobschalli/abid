require_relative 'test_helper'

class RideBoardTest < AbidTest
  def test_pool_holds_only_unassigned_active_riders
    event = make_event
    driver = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    make_rider(event, 'seated', zone: ZONE_1, driver: driver)
    waiting = make_rider(event, 'waiting', zone: ZONE_1)
    make_rider(event, 'away', zone: ZONE_1, status: 'no_show')

    board = RideBoard.new(event)

    assert_equal [waiting.id], board.pool.map(&:id)
    assert_equal 1, board.pool_count
    assert_equal 1, board.seated_count
  end

  def test_queue_groups_by_zone_and_drops_empty_zones
    event = make_event
    make_rider(event, 'north one', zone: ZONE_3)
    make_rider(event, 'north two', zone: ZONE_3)
    make_rider(event, 'east one', zone: ZONE_5)

    groups = RideBoard.new(event).queue_groups

    # In Location::ZONES order, not insertion order.
    assert_equal [ZONE_3, ZONE_5], groups.map { |g| g[:zone] }
    assert_equal [2, 1], groups.map { |g| g[:count] }
  end

  def test_riders_without_a_zone_land_in_unzoned
    event = make_event
    make_rider(event, 'nowhere')

    groups = RideBoard.new(event).queue_groups

    assert_equal ['Unzoned'], groups.map { |g| g[:zone] }
  end

  # The queue used to build its groups from Location::ZONES alone, so a rider
  # holding a zone that was not in that list matched no bucket and was not nil
  # either — they vanished from the queue while pool_count still counted them.
  # The footer said "3 waiting" above a queue showing one.
  def test_every_waiting_rider_appears_in_exactly_one_group
    event = make_event
    make_rider(event, 'known', zone: ZONE_1)
    make_rider(event, 'nowhere')
    # Ride has no inclusion validation, so a stale value persists exactly as it
    # did in production before migration 2600.
    make_rider(event, 'stale').update_column(:zone, 'Atlantis')

    board = RideBoard.new(event)

    assert_equal 3, board.pool_count
    assert_equal board.pool_count, board.queue_groups.sum { |g| g[:count] },
                 'a waiting rider is missing from the queue'
  end

  def test_an_unrecognised_zone_is_labelled_not_folded_into_unzoned
    event = make_event
    make_rider(event, 'nowhere')
    make_rider(event, 'stale').update_column(:zone, 'Atlantis')

    labels = RideBoard.new(event).queue_groups.map { |g| g[:zone] }

    assert_includes labels, 'Unzoned'
    assert_includes labels, 'Atlantis (unrecognised)'
  end

  def test_filter_matches_name_or_zone
    event = make_event
    make_rider(event, 'caitlin', zone: ZONE_1)
    make_rider(event, 'emilio', zone: ZONE_5)

    assert_equal ['caitlin'], RideBoard.new(event, query: 'cait').visible_pool.map(&:display_name)
    assert_equal ['emilio'], RideBoard.new(event, query: ZONE_5.downcase).visible_pool.map(&:display_name)
    assert_empty RideBoard.new(event, query: 'nobody').visible_pool
  end

  def test_seat_counts
    event = make_event
    driver = make_driver(event, 'tobin', seats: 6, zone: ZONE_5)
    2.times { |i| make_rider(event, "seated #{i}", zone: ZONE_5, driver: driver) }

    board = RideBoard.new(event)
    car = board.cars.first

    assert_equal 6, car.seats
    assert_equal 2, car.used
    assert_equal 4, car.seats_free
    assert_equal 4, board.seats_left
    refute car.full?
    refute car.over?
  end

  def test_driver_seats_override_user_capacity
    event = make_event
    user = make_user('van driver', capacity: 4, zone: ZONE_1)
    event.rides.create!(user: user, role: 'driver', seats: 14, zone: ZONE_1)

    assert_equal 14, RideBoard.new(event).cars.first.seats
  end

  def test_flags_a_car_over_capacity
    event = make_event
    driver = make_driver(event, 'caleb', seats: 1, zone: ZONE_3)
    2.times { |i| make_rider(event, "over #{i}", zone: ZONE_3, driver: driver) }

    board = RideBoard.new(event)

    assert board.cars.first.over?
    assert_equal 1, board.overfull_count
    assert_includes board.warning_text, 'over capacity'
  end

  def test_detects_a_clash_inside_one_car
    event = make_event
    driver = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    one = make_rider(event, 'kenzo', zone: ZONE_1, driver: driver)
    two = make_rider(event, 'ronin', zone: ZONE_1, driver: driver)
    Clash.add(one.user_id, two.user_id)

    board = RideBoard.new(event)
    car = board.cars.first

    assert car.conflict?(car.passengers.find { |p| p.id == one.id })
    assert_equal 2, board.conflict_count
    assert_includes board.warning_text, 'clash'
  end

  def test_no_clash_when_the_other_person_is_in_a_different_car
    event = make_event
    a = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    b = make_driver(event, 'caleb', seats: 4, zone: ZONE_1)
    one = make_rider(event, 'kenzo', zone: ZONE_1, driver: a)
    two = make_rider(event, 'ronin', zone: ZONE_1, driver: b)
    Clash.add(one.user_id, two.user_id)

    assert_equal 0, RideBoard.new(event).conflict_count
  end

  def test_fit_pill_reflects_the_selected_rider
    event = make_event
    near = make_driver(event, 'near', seats: 4, zone: ZONE_5)
    far = make_driver(event, 'far', seats: 1, zone: ZONE_3)
    make_rider(event, 'blocker', zone: ZONE_3, driver: far)
    rider = make_rider(event, 'renata', zone: ZONE_5)

    board = RideBoard.new(event, selected_ride_id: rider.id)
    by_name = board.cars.index_by(&:name)

    assert_equal :closest, by_name['near'].fit_for(board.selected)
    assert_equal :full, by_name['far'].fit_for(board.selected)
  end

  def test_warning_free_board_reports_nothing
    event = make_event
    driver = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    make_rider(event, 'caitlin', zone: ZONE_1, driver: driver)

    assert_empty RideBoard.new(event).warnings
  end

  def test_sibling_events_are_the_other_slots_that_day
    starts = Time.zone.now.change(hour: 9, min: 30) + 1.day
    early = make_event(name: 'Sunday School', starts: starts)
    late = make_event(name: 'Sunday Service', starts: starts + 1.hour)
    make_event(name: 'Friday Study', starts: starts + 3.days)

    assert_equal [early.id, late.id], RideBoard.new(early).sibling_events.map(&:id)
  end

  # The board's only navigation. These step relative to the event on screen,
  # not to Time.zone.now — otherwise they answer the wrong question as soon as
  # you are looking at a board from last Sunday.
  def test_next_and_previous_step_through_events_in_time_order
    starts = Time.zone.now.change(hour: 9, min: 30) + 1.day
    early = make_event(name: 'Sunday School', starts: starts)
    late = make_event(name: 'Sunday Service', starts: starts + 1.hour)
    friday = make_event(name: 'Friday Study', starts: starts + 5.days)

    assert_equal late.id, RideBoard.new(early).next_event.id
    assert_equal friday.id, RideBoard.new(late).next_event.id
    assert_equal late.id, RideBoard.new(friday).previous_event.id
    assert_equal early.id, RideBoard.new(late).previous_event.id
  end

  def test_stepping_past_either_end_gives_nothing
    only = make_event(name: 'Sunday Service', starts: Time.zone.now + 1.day)

    assert_nil RideBoard.new(only).next_event
    assert_nil RideBoard.new(only).previous_event
  end

  def test_stepping_works_backwards_from_a_past_event
    past = make_event(name: 'Last Sunday', starts: Time.zone.now - 7.days)
    soon = make_event(name: 'This Sunday', starts: Time.zone.now + 1.day)

    assert_equal soon.id, RideBoard.new(past).next_event.id,
                 'next must be relative to the event shown, not to now'
  end

  def test_an_event_with_no_start_time_has_no_neighbours
    # Events made through the Discord modal can have no start_time, and there
    # is no sensible "the one after this" from a point off the timeline.
    make_event(name: 'Sunday Service', starts: Time.zone.now + 1.day)
    undated = Event.create!(name: 'Someday')

    assert_nil RideBoard.new(undated).next_event
    assert_nil RideBoard.new(undated).previous_event
  end

  def test_a_disabled_event_is_never_stepped_to
    starts = Time.zone.now + 1.day
    first = make_event(name: 'Sunday School', starts: starts)
    Event.create!(name: 'Cancelled', start_time: starts + 1.hour, disabled: true)
    real = make_event(name: 'Sunday Service', starts: starts + 2.hours)

    assert_equal real.id, RideBoard.new(first).next_event.id
  end
end
