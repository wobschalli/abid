# Demo data for working on the ride board without a Discord server attached.
#
#   rake db:demo
#
# Safe to re-run: everything is find_or_create_by on a marker discord_id range.
# Nothing here touches real rows — demo users live at discord_id 900000000+.
require_relative '../config/environment'

Abid.establish_connection
Abid.load_models

DEMO_ID_BASE = 900_000_000
DEMO_PASSWORD = 'ridedemo'.freeze

puts "seeding demo data into #{Abid.env}…"

# --- locations --------------------------------------------------------------

LOCATIONS = {
  'North' => [
    ['1420 Ridgeway Ave', 40.4600, -86.9200],
    ['88 Marlow Ct', 40.4650, -86.9300]
  ],
  'Campus' => [
    ['Harker Hall lot', 40.4259, -86.9081],
    ['Eastgate Apts, lot B', 40.4280, -86.9150]
  ],
  'Downtown' => [
    ['4th & Pine', 40.4167, -86.8753],
    ['901 Grand Ave', 40.4190, -86.8800]
  ],
  'East' => [
    ['77 Lakeshore Dr', 40.4300, -86.8500],
    ['1102 Oakvale', 40.4350, -86.8550]
  ]
}.freeze

locations = LOCATIONS.flat_map do |zone, entries|
  entries.map do |name, lat, lon|
    Location.find_or_create_by(name: name) do |l|
      l.lat = lat
      l.lon = lon
      l.zone = zone
    end.tap { |l| l.update(zone: zone) if l.zone != zone }
  end
end

by_zone = locations.group_by(&:zone)

# --- people -----------------------------------------------------------------

# name, seats (nil = rider), zone
PEOPLE = [
  ['alan', nil, 'Downtown'],
  ['ian', 4, 'Campus'],
  ['caleb', 3, 'North'],
  ['tobin', 6, 'East'],
  ['christina', 4, 'Downtown'],
  ['ranbir', 4, 'North'],
  ['caitlin', nil, 'Campus'],
  ['jalen', nil, 'Campus'],
  ['kenzo', nil, 'Campus'],
  ['maribel', nil, 'North'],
  ['kylan r', nil, 'North'],
  ['juno wa', nil, 'North'],
  ['renata', nil, 'East'],
  ['emilio', nil, 'East'],
  ['ronin', nil, 'East'],
  ['dalton', nil, 'Downtown'],
  ['irene', nil, 'Downtown'],
  ['luna cheng', nil, 'Campus'],
  ['tim', nil, 'East'],
  ['flora', nil, 'East'],
  ['justin', nil, 'North'],
  ['lydia', nil, 'Downtown'],
  ['nate', nil, 'Campus']
].freeze

users = PEOPLE.each_with_index.map do |(name, seats, zone), index|
  User.find_or_create_by(discord_id: DEMO_ID_BASE + index) do |u|
    u.name = name
    u.username = name.tr(' ', '')
    u.password = DEMO_PASSWORD
    u.password_confirmation = DEMO_PASSWORD
  end.tap do |u|
    u.update(
      capacity: seats,
      location: by_zone[zone].sample,
      leader: %w[alan ian].include?(name)
    )
  end
end

by_name = users.index_by(&:name)

# --- events -----------------------------------------------------------------

# Next Sunday, so /board's "next upcoming" lookup finds it.
sunday = Time.zone.today + ((7 - Time.zone.today.wday) % 7)
sunday += 7 if sunday == Time.zone.today

def demo_event(name, section, day, hour, minute)
  starts = Time.zone.local(day.year, day.month, day.day, hour, minute)
  Event.find_or_create_by(name: name, start_time: starts) do |e|
    e.section = section
    e.end_time = starts + 90.minutes
    e.message_rides_at = starts - 24.hours
    e.collect_rides_at = starts - 2.hours
    e.message = "React if you need a ride to #{name}."
    e.disabled = false
  end
end

sunday_school = demo_event('Sunday School', 'early', sunday, 9, 30)
service = demo_event('Sunday Service', 'late', sunday, 10, 30)

friday = sunday - 2
friday_early = demo_event('Friday Bible Study', 'early', friday, 18, 30)
friday_late = demo_event('Friday Bible Study', 'late', friday, 20, 0)

# --- rides ------------------------------------------------------------------

def seat(event, user, role:, driver: nil)
  ride = event.rides.find_or_initialize_by(user_id: user.id)
  ride.role = role
  ride.status = driver ? 'assigned' : 'requested'
  ride.zone = user.location&.zone
  ride.seats = user.capacity if role == 'driver'
  ride.pickup_address = user.location&.name
  ride.pickup_location = user.location
  ride.driver_ride = driver
  ride.signed_up_at = Time.zone.now
  ride.save!
  ride
end

[sunday_school, service].each { |event| event.rides.destroy_all }

drivers = {}
%w[ian caleb tobin christina].each do |name|
  drivers[name] = seat(sunday_school, by_name[name], role: 'driver')
end

# A few pre-seated riders so the board isn't a blank grid, and a healthy queue
# left over for Auto-fill to chew on.
{
  'ian' => ['caitlin', 'jalen', 'kenzo'],
  'caleb' => ['kylan r', 'juno wa'],
  'tobin' => ['renata', 'emilio', 'ronin'],
  'christina' => ['irene', 'dalton']
}.each do |driver_name, rider_names|
  rider_names.each { |rider| seat(sunday_school, by_name[rider], role: 'rider', driver: drivers[driver_name]) }
end

['luna cheng', 'tim', 'flora', 'justin', 'lydia', 'nate', 'maribel'].each do |name|
  seat(sunday_school, by_name[name], role: 'rider')
end

# Second slot, so the slot tabs have something to switch between.
seat(service, by_name['ranbir'], role: 'driver')
['caitlin', 'luna cheng', 'nate', 'irene'].each do |name|
  seat(service, by_name[name], role: 'rider')
end

# Friday too, so that whichever occurrence is next when you open /board has
# something on it rather than an empty grid.
[friday_early, friday_late].each { |event| event.rides.destroy_all }

friday_driver = seat(friday_early, by_name['ian'], role: 'driver')
seat(friday_early, by_name['caleb'], role: 'driver')
['caitlin', 'jalen'].each { |n| seat(friday_early, by_name[n], role: 'rider', driver: friday_driver) }
['tim', 'flora', 'justin', 'lydia'].each { |n| seat(friday_early, by_name[n], role: 'rider') }

seat(friday_late, by_name['tobin'], role: 'driver')
['renata', 'emilio'].each { |n| seat(friday_late, by_name[n], role: 'rider') }

# --- clashes ----------------------------------------------------------------

# 'kenzo' and 'ronin' are in different cars; 'tim' and 'justin' are both in the
# queue, so Auto-fill has to keep them apart.
Clash.add(by_name['kenzo'].id, by_name['ronin'].id)
Clash.add(by_name['tim'].id, by_name['justin'].id)
Clash.add(by_name['dalton'].id, by_name['irene'].id) # deliberately seated together: shows the warning

puts <<~SUMMARY

  done.

    #{User.where('discord_id >= ?', DEMO_ID_BASE).count} demo users
    #{Event.count} events (#{sunday_school.rides.count} rides on #{sunday_school.name})

  Log in at /login as any of these, password "#{DEMO_PASSWORD}":

    alan   (leader — can edit the board)
    ian    (leader)
    nate   (not a leader — read-only board)

  Then open /board
SUMMARY
