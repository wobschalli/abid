require_relative 'test_helper'

class AssignmentHistoryTest < AbidTest
  def test_undo_puts_a_rider_back_where_they_were
    event = make_event
    a = make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    b = make_driver(event, 'caleb', seats: 4, zone: ZONE_3)
    rider = make_rider(event, 'caitlin', zone: ZONE_1, driver: a)

    session = {}
    history = AssignmentHistory.new(session, event)
    history.record([rider])
    rider.update!(driver_ride_id: b.id, status: 'assigned')

    AssignmentHistory.new(session, event).undo!

    assert_equal a.id, rider.reload.driver_ride_id
  end

  def test_undo_restores_status_too
    event = make_event
    make_driver(event, 'ian', seats: 4, zone: ZONE_1)
    rider = make_rider(event, 'caitlin', zone: ZONE_1)

    session = {}
    history = AssignmentHistory.new(session, event)
    history.record([rider])
    rider.update!(status: 'no_show')

    AssignmentHistory.new(session, event).undo!

    assert_equal 'requested', rider.reload.status
  end

  def test_one_autofill_is_a_single_undo_step
    event = make_event
    make_driver(event, 'ian', seats: 6, zone: ZONE_1)
    riders = 3.times.map { |i| make_rider(event, "rider #{i}", zone: ZONE_1) }

    session = {}
    history = AssignmentHistory.new(session, event)
    history.record(event.rides.unassigned.to_a)
    AutoFiller.new(event).call

    restored = AssignmentHistory.new(session, event).undo!

    assert_equal 3, restored
    riders.each { |r| assert_nil r.reload.driver_ride_id }
    refute AssignmentHistory.new(session, event).any?
  end

  def test_undo_with_nothing_recorded_is_a_no_op
    event = make_event
    assert_equal 0, AssignmentHistory.new({}, event).undo!
  end

  def test_keeps_at_most_ten_steps
    event = make_event
    rider = make_rider(event, 'caitlin', zone: ZONE_1)

    session = {}
    12.times { AssignmentHistory.new(session, event).record([rider]) }

    assert_equal AssignmentHistory::LIMIT, session["undo_#{event.id}"].size
  end

  def test_history_is_scoped_per_event
    a = make_event(name: 'Early')
    b = make_event(name: 'Late')
    rider = make_rider(a, 'caitlin', zone: ZONE_1)

    session = {}
    AssignmentHistory.new(session, a).record([rider])

    assert AssignmentHistory.new(session, a).any?
    refute AssignmentHistory.new(session, b).any?
  end

  def test_undo_ignores_rides_deleted_since
    event = make_event
    rider = make_rider(event, 'caitlin', zone: ZONE_1)

    session = {}
    AssignmentHistory.new(session, event).record([rider])
    rider.destroy

    assert_equal 0, AssignmentHistory.new(session, event).undo!
  end
end
