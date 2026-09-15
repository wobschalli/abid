require_relative 'test_helper'

class DriverLoadTest < AbidTest
  # Finished occurrences, newest last in this array.
  def past_events(count, from: 8.weeks.ago)
    (0...count).map do |i|
      make_event(name: "Service #{i}", starts: from + (i * 7).days)
    end
  end

  def drove(event, user)
    event.rides.create!(user: user, role: 'driver', status: 'confirmed', seats: 4)
  end

  def rode(event, user)
    event.rides.create!(user: user, role: 'rider', status: 'assigned')
  end

  def test_counts_only_finished_occurrences
    user = make_user('caleb', capacity: 4)
    past = past_events(2)
    upcoming = make_event(name: 'Next week', starts: 3.days.from_now)
    past.each { |e| drove(e, user) }
    drove(upcoming, user)

    load = DriverLoad.new

    assert_equal 2, load.window_size
    assert_equal 2, load.drove(user)
  end

  def test_window_caps_how_far_back_it_looks
    user = make_user('caleb', capacity: 4)
    past_events(10).each { |e| drove(e, user) }

    load = DriverLoad.new(window: 4)

    assert_equal 4, load.window_size
    assert_equal 4, load.drove(user)
  end

  def test_separates_driving_from_riding
    driver = make_user('caleb', capacity: 4)
    rider = make_user('caitlin')
    events = past_events(3)
    events.each { |e| drove(e, driver) }
    events.first(2).each { |e| rode(e, rider) }

    load = DriverLoad.new

    assert_equal 3, load.drove(driver)
    assert_equal 0, load.rode(driver)
    assert_equal 0, load.drove(rider)
    assert_equal 2, load.rode(rider)
  end

  def test_ignores_people_who_dropped_out
    user = make_user('flaky')
    event = past_events(1).first
    rode(event, user).update!(status: 'no_show')

    assert_equal 0, DriverLoad.new.rode(user)
  end

  def test_summary_reads_as_a_sentence
    user = make_user('caleb', capacity: 4)
    events = past_events(4)
    events.first(3).each { |e| drove(e, user) }

    assert_equal 'drove 3 of the last 4', DriverLoad.new.summary(user)
  end

  # Nothing to say beats "0 of 0".
  def test_summary_is_nil_for_someone_with_no_history
    user = make_user('newcomer')
    past_events(2)

    assert_nil DriverLoad.new.summary(user)
  end

  def test_summary_is_nil_when_nothing_has_happened_yet
    user = make_user('caleb', capacity: 4)

    assert_nil DriverLoad.new.summary(user)
  end

  # The point of keeping every past occurrence: noticing before someone burns
  # out, not after they stop coming.
  def test_flags_someone_carrying_more_than_their_share
    heavy = make_user('caleb', capacity: 4)
    light = make_user('ian', capacity: 4)
    events = past_events(5)
    events.first(4).each { |e| drove(e, heavy) }
    events.first(1).each { |e| drove(e, light) }

    load = DriverLoad.new

    assert load.heavy_load?(heavy)
    refute load.heavy_load?(light)
  end

  # Two of the last two is not evidence of anything yet.
  def test_does_not_flag_on_a_tiny_sample
    user = make_user('caleb', capacity: 4)
    past_events(2).each { |e| drove(e, user) }

    refute DriverLoad.new.heavy_load?(user)
  end

  def test_counts_are_one_query_not_one_per_user
    users = 3.times.map { |i| make_user("driver #{i}", capacity: 4) }
    events = past_events(2)
    events.each { |e| users.each { |u| drove(e, u) } }

    load = DriverLoad.new
    load.recent_events # warm

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      users.each { |u| load.drove(u) }
    end

    assert_operator queries, :<=, 1, 'per-user queries crept in'
  end
end
