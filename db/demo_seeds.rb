# Demo data for working on the ride board without a Discord server attached.
#
#   rake db:demo
#
# Safe to re-run: everything is find_or_create_by on a marker discord_id range.
# Nothing here touches real rows — demo users live at discord_id 900000000+.
require_relative '../config/environment'

Abid.establish_connection
Abid.load_models
Abid.load_services # EventGenerator

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
friday = sunday - 2

# Recurring slots. Occurrences are generated from these, one Event row per week.
def demo_series(name, section, weekday, hour, minute, location)
  EventSeries.find_or_create_by(name: name, section: section) do |s|
    s.weekday = weekday
    s.start_time_of_day = Time.zone.parse(format('%02d:%02d', hour, minute))
    s.end_time_of_day = Time.zone.parse(format('%02d:%02d', hour + 1, minute))
    s.message_lead_hours = 24
    s.collect_lead_hours = 2
    s.horizon_weeks = 3
    s.location = location
    s.message = "React if you need a ride to #{name}."
  end
end

# --- discord scaffolding ----------------------------------------------------

# Stand-ins so channel-bound features have something to point at without a real
# Discord server. Real ids arrive via db/seeds.rb + the bot's Setup sync.
demo_server = Server.find_or_create_by(name: 'Abide (demo)') do |s|
  s.discord_id = DEMO_ID_BASE + 1
end
rides_channel = Channel.find_or_create_by(discord_id: DEMO_ID_BASE + 2) do |c|
  c.name = 'rides'
  c.server = demo_server
end

RECURRING_NAMES = ['Sunday School', 'Sunday Service', 'Friday Bible Study'].freeze

# Earlier versions of this seed created these as one-off events. They are now
# generated from a series, so drop the orphans — otherwise every slot shows up
# twice in /events, once WEEKLY and once ONE-OFF. db:demo owns these names.
orphans = Event.one_off.where(name: RECURRING_NAMES)
puts "  removing #{orphans.count} stale one-off demo events" if orphans.any?
orphans.destroy_all

church = Location.find_by(name: 'Harker Hall lot')
school_series  = demo_series('Sunday School', 'early', 0, 9, 30, church)
service_series = demo_series('Sunday Service', 'late', 0, 10, 30, church)
friday_early_series = demo_series('Friday Bible Study', 'early', 5, 18, 30, church)
friday_late_series  = demo_series('Friday Bible Study', 'late', 5, 20, 0, church)

EventGenerator.call(from: Time.zone.today)

sunday_school = school_series.ensure_occurrence(sunday)
service       = service_series.ensure_occurrence(sunday)
friday_early  = friday_early_series.ensure_occurrence(friday)
friday_late   = friday_late_series.ensure_occurrence(friday)

# A one-off, to show the other badge and prove non-recurring events still work.
retreat_start = Time.zone.local(sunday.year, sunday.month, sunday.day, 7, 0) + 21.days
retreat = Event.find_or_create_by(name: 'Fall Retreat', start_time: retreat_start) do |e|
  e.end_time = retreat_start + 10.hours
  e.message_rides_at = retreat_start - 72.hours
  e.collect_rides_at = retreat_start - 12.hours
  e.location = church
  e.message = 'React if you need a ride to the retreat. Leaving 7am sharp.'
end

# A finished occurrence two weeks back, so the Past tab and the read-only
# roster have something real in them.
past_sunday = sunday - 14
past_event = school_series.ensure_occurrence(past_sunday)
past_event&.update!(collected_at: past_sunday.to_time + 8.hours, rides_message_id: nil)

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

# The retreat: a one-off with a full car.
retreat.rides.destroy_all
retreat_driver = seat(retreat, by_name['tobin'], role: 'driver')
['renata', 'emilio', 'ronin', 'flora'].each do |n|
  seat(retreat, by_name[n], role: 'rider', driver: retreat_driver)
end

# A completed past occurrence — everyone seated, nobody left waiting.
if past_event
  past_event.rides.destroy_all
  past_drivers = %w[ian caleb].to_h { |n| [n, seat(past_event, by_name[n], role: 'driver')] }
  {
    'ian' => ['caitlin', 'jalen', 'kenzo'],
    'caleb' => ['kylan r', 'juno wa', 'maribel']
  }.each do |driver_name, riders|
    riders.each { |r| seat(past_event, by_name[r], role: 'rider', driver: past_drivers[driver_name]) }
  end
  # One person who said yes and then didn't turn up.
  seat(past_event, by_name['tim'], role: 'rider').update!(status: 'no_show')
end

# --- sign-up posts ----------------------------------------------------------

SignupPost.where(channel: rides_channel).destroy_all

def build_signup(channel, date, author, options, **attrs)
  post = SignupPost.create!({ channel: channel, service_date: date, created_by: author }.merge(attrs))
  options.each_with_index do |(emoji, event, label), index|
    post.options.create!(
      Signup::EmojiKey.parse(emoji).merge(event: event, label: label, position: index)
    )
  end
  post.reload
end

# One already sent and collecting reactions.
live = build_signup(
  rides_channel, sunday, by_name['alan'],
  [['1️⃣', sunday_school, '9:00am — Sunday School'],
   ['2️⃣', service, '10:30am — Sunday Service']],
  post_at: Time.zone.now - 2.hours
)
live.mark_posted!(DEMO_ID_BASE + 1000, body: live.body)

# Reactions arriving, as the gateway would deliver them.
sink = Signup::ReactionSink.new
['luna cheng', 'tim', 'flora'].each do |name|
  sink.add(message_id: live.discord_message_id, emoji_key: 'u:one',
           discord_user_id: by_name[name].discord_id, username: name)
end
sink.add(message_id: live.discord_message_id, emoji_key: 'u:two',
         discord_user_id: by_name['nate'].discord_id, username: 'nate')

# One queued to go out later, so the scheduled state has an example.
build_signup(
  rides_channel, friday, by_name['ian'],
  [['1️⃣', friday_early, '6:30pm — early'],
   ['2️⃣', friday_late, '8:00pm — late']],
  post_at: Time.zone.now + 1.day, status: 'scheduled'
)

# And a half-built draft.
build_signup(rides_channel, sunday + 7, by_name['alan'], [['1️⃣', nil, nil]])

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
