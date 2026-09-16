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

# Real West Lafayette places, shared with db/seeds.rb. This file used to invent
# eight fictional streets; those are gone.
require_relative 'locations'
Abid::Locations.seed!

# The eight invented streets earlier versions of this file created. They still
# exist in any database seeded before the real list landed, and migration 2600
# gave them real-looking zone names, so they are no longer distinguishable by
# eye. References are nulled first — rides.pickup_location_id has a foreign key
# and would otherwise refuse the delete.
FICTIONAL = ['Harker Hall lot', 'Eastgate Apts, lot B', '4th & Pine', '901 Grand Ave',
             '1420 Ridgeway Ave', '88 Marlow Ct', '77 Lakeshore Dr', '1102 Oakvale'].freeze

stale_locations = Location.where(name: FICTIONAL)
if stale_locations.any?
  ids = stale_locations.pluck(:id)
  puts "  removing #{ids.size} invented demo locations"
  Ride.where(pickup_location_id: ids).update_all(pickup_location_id: nil)
  User.where(location_id: ids).update_all(location_id: nil)
  Event.where(location_id: ids).update_all(location_id: nil)
  EventSeries.where(location_id: ids).update_all(location_id: nil)
  Location.where(id: ids).delete_all
end

by_zone = Location.zoned.group_by(&:zone)
missing = Location::ZONES - by_zone.keys
raise "no seeded locations in #{missing.join(', ')}" if missing.any?

# --- people -----------------------------------------------------------------

# name, seats (nil = rider), zone
PEOPLE = [
  ['alan', nil, 'Chauncey'],
  ['ian', 4, 'On-campus'],
  ['caleb', 3, 'Northwestern'],
  ['tobin', 6, 'Lafayette'],
  ['christina', 4, 'Chauncey'],
  ['ranbir', 4, 'Northwestern'],
  ['caitlin', nil, 'On-campus'],
  ['jalen', nil, 'On-campus'],
  ['kenzo', nil, 'On-campus'],
  ['maribel', nil, 'Northwestern'],
  ['kylan r', nil, 'Northwestern'],
  ['juno wa', nil, 'Northwestern'],
  ['renata', nil, 'Lafayette'],
  ['emilio', nil, 'Lafayette'],
  ['ronin', nil, 'Lafayette'],
  ['dalton', nil, 'Chauncey'],
  ['irene', nil, 'Chauncey'],
  ['luna cheng', nil, 'On-campus'],
  ['tim', nil, 'Lafayette'],
  ['flora', nil, 'Lafayette'],
  ['justin', nil, 'Northwestern'],
  ['lydia', nil, 'Chauncey'],
  ['nate', nil, 'On-campus']
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
      leader: %w[alan ian].include?(name),
      # Drivers need a way to reach a rider waiting outside an apartment block.
      phone: format('(765) 555-%04d', 100 + index)
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

# find_by! not find_by: a nil venue here is silent and total — every series and
# the retreat get a nil location, RoutePlanner#destination_stop returns nil, and
# no driver DM in the whole demo dataset gets a maps link, with no error
# anywhere. Also a real place now, not an invented one.
church = Location.find_by!(name: Abid::Locations::GLCAC)
school_series  = demo_series('Sunday School', 'early', 0, 9, 30, church)
service_series = demo_series('Sunday Service', 'late', 0, 10, 30, church)
friday_early_series = demo_series('Friday Bible Study', 'early', 5, 18, 30, church)
friday_late_series  = demo_series('Friday Bible Study', 'late', 5, 20, 0, church)

# Purdue's calendar. Approximate windows — correct them on /series. Without
# these the bot posts sign-ups into an empty server every week of December.
year = sunday.year
[
  ['Thanksgiving break', Date.new(year, 11, 25), Date.new(year, 11, 29)],
  ['Winter break', Date.new(year, 12, 13), Date.new(year + 1, 1, 11)],
  ['Spring break', Date.new(year + 1, 3, 14), Date.new(year + 1, 3, 22)],
  ['Summer', Date.new(year + 1, 5, 9), Date.new(year + 1, 8, 16)]
].each do |name, starts_on, ends_on|
  AcademicBreak.find_or_create_by(name: name) do |b|
    b.starts_on = starts_on
    b.ends_on = ends_on
  end
end

EventGenerator.call(from: Time.zone.today)

sunday_school = school_series.ensure_occurrence(sunday)
service       = service_series.ensure_occurrence(sunday)
friday_early  = friday_early_series.ensure_occurrence(friday)
friday_late   = friday_late_series.ensure_occurrence(friday)

# A one-off, to show the other badge and prove non-recurring events still work.
retreat_start = Time.zone.local(sunday.year, sunday.month, sunday.day, 7, 0) + 21.days
retreat = Event.find_or_create_by(name: 'Fall Retreat', start_time: retreat_start) do |e|
  e.end_time = retreat_start + 10.hours
  e.location = church
  e.message = 'React if you need a ride to the retreat. Leaving 7am sharp.'
end

# Finished occurrences going back two months, so the Past tab has history and
# the driving-load column on /users has a window worth measuring. The rota is
# deliberately lopsided — caleb drives almost every week — so the "carrying
# more than their share" flag has something real to catch.
past_sundays = (1..8).map { |weeks_ago| sunday - (weeks_ago * 7) }
past_events = past_sundays.filter_map do |date|
  event = school_series.ensure_occurrence(date)
  event
end
past_event = past_events.first

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

# Completed occurrences. The rota is deliberately uneven — caleb drives seven
# of the last eight, ian three, tobin and christina once each — so the members
# page has a real "carrying more than their share" case to show rather than a
# flat, uninformative history.
ROTA = [
  %w[caleb ian],
  %w[caleb],
  %w[caleb tobin],
  %w[caleb ian],
  %w[caleb],
  %w[caleb christina],
  %w[ian],
  %w[caleb]
].freeze

RIDER_POOL = ['caitlin', 'jalen', 'kenzo', 'kylan r', 'juno wa', 'maribel',
              'luna cheng', 'renata', 'dalton', 'irene'].freeze

past_events.each_with_index do |event, index|
  event.rides.destroy_all
  driver_names = ROTA[index % ROTA.size]
  drivers_here = driver_names.to_h { |n| [n, seat(event, by_name[n], role: 'driver')] }

  # Rotate who rides so the roster differs week to week.
  riders = RIDER_POOL.rotate(index * 3).first(driver_names.size * 3)
  riders.each_with_index do |rider_name, i|
    driver = drivers_here[driver_names[i % driver_names.size]]
    seat(event, by_name[rider_name], role: 'rider', driver: driver)
  end

  # One person who said yes and then didn't turn up, on the most recent one.
  seat(event, by_name['tim'], role: 'rider').update!(status: 'no_show') if index.zero?
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
