ENV['ABID_ENV'] ||= 'test'

require_relative '../config/environment'

Abid.establish_connection
Abid.load_models
Abid.load_services

require 'minitest/autorun'

# Base case for the ride board logic. Each test runs inside a transaction that
# is rolled back afterwards, so tests can build whatever data they need without
# cleaning up after each other.
class AbidTest < Minitest::Test
  DISCORD_ID_BASE = 800_000_000

  # Positional, not semantic. Almost every test needs "a zone" or "a different
  # zone", and route_planner_test needs "a zone that sorts before another" —
  # which by definition is ZONE_1 vs ZONE_2. Naming them by ordinal means the
  # next time the zone vocabulary changes, no test needs touching.
  ZONE_1, ZONE_2, ZONE_3, ZONE_4, ZONE_5 = Location::ZONES

  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @discord_seq = 0
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end

  private

  def next_discord_id
    @discord_seq += 1
    DISCORD_ID_BASE + (Process.pid % 1000) * 10_000 + @discord_seq
  end

  def location_in(zone)
    @locations ||= {}
    @locations[zone] ||= Location.create!(name: "#{zone} pickup", zone: zone)
  end

  def make_user(name, capacity: nil, zone: nil)
    User.create!(
      discord_id: next_discord_id,
      name: name,
      username: name.tr(' ', ''),
      capacity: capacity,
      location: zone && location_in(zone),
      password: 'testpassword',
      password_confirmation: 'testpassword'
    )
  end

  def make_event(name: 'Sunday Service', starts: nil)
    starts ||= Time.zone.now + 1.day
    Event.create!(name: name, start_time: starts, end_time: starts + 1.hour)
  end

  def make_driver(event, name, seats:, zone: nil)
    user = make_user(name, capacity: seats, zone: zone)
    event.rides.create!(
      user: user, role: 'driver', status: 'confirmed',
      seats: seats, zone: zone
    )
  end

  def make_rider(event, name, zone: nil, driver: nil, status: nil)
    user = make_user(name, zone: zone)
    event.rides.create!(
      user: user, role: 'rider', zone: zone,
      driver_ride: driver,
      status: status || (driver ? 'assigned' : 'requested')
    )
  end
end
