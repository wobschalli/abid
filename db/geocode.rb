# Refine the approximate coordinates in db/locations.rb against OpenStreetMap.
#
#   rake db:geocode            # only locations with no coordinates
#   GEOCODE_ALL=1 rake db:geocode   # re-check everything
#
# Nominatim's usage policy is one request per second, so this is deliberately
# slow and deliberately not run at seed time: a seed that depends on a third
# party is non-deterministic and fails on a plane.
#
# Nothing is written unless the result lands inside the Tippecanoe County
# bounding box — a search that drifts to a Lark in Nevada should be reported,
# not saved.
require_relative '../config/environment'

Abid.establish_connection
Abid.load_models
# After load_models: map/map.rb requires models/location.rb, which subclasses
# ApplicationRecord and blows up if it is loaded first.
require_relative '../map/map'

PAUSE = 1.1
# Roughly two blocks. Wide enough that a genuine refinement — the eyeballed
# seed coordinates were good to about a block — passes without fuss, tight
# enough that landing on the wrong road does not.
MAX_DRIFT = 500

map = Map.new
scope = ENV['GEOCODE_ALL'] == '1' ? Location.all : Location.where(lat: nil).or(Location.where(lon: nil))
scope = scope.order(:name).to_a

if scope.empty?
  puts 'Every location already has coordinates. Use GEOCODE_ALL=1 to re-check them.'
  exit
end

puts "geocoding #{scope.size} locations (about #{(scope.size * PAUSE).round}s)…"

updated = 0
missed = []

scope.each do |location|
  # Address first: a street is a map feature, a leasing brand is not. The city
  # comes from the location's own zone rather than being hardcoded — Lafayette
  # is across the river from West Lafayette and has its own State Street.
  query = location.geocode_query
  result = map.addr_to_coord(query)
  sleep PAUSE

  if result[:lat].blank? || result[:lon].blank?
    missed << [location.name, location.address.present? ? 'no result' : 'no result — needs a street address']
    next
  end

  lat = result[:lat].to_f
  lon = result[:lon].to_f

  # Map::BOXES[:tippecanoe] is lon_min, lat_min, lon_max, lat_max.
  lon_min, lat_min, lon_max, lat_max = Map::BOXES[:tippecanoe].map(&:to_f)
  unless lat.between?(lat_min, lat_max) && lon.between?(lon_min, lon_max)
    missed << [location.name, format('outside Tippecanoe (%.4f, %.4f)', lat, lon)]
    next
  end

  moved = location.coords? ? Math.sqrt(((location.lat.to_f - lat)**2) + ((location.lon.to_f - lon)**2)) * 111_000 : nil

  # A big jump is not a refinement, it is a different place. The church proved
  # this: "3501 W 250 N" forward-geocodes onto "3501 N 250 W", a road 2.8km
  # away and still inside the county, so the bounding box does not catch it.
  # Overwriting a coordinate we know is right — that one reverse-geocodes to
  # the church by name — with a plausible wrong one is the worst outcome here,
  # because nothing downstream would look wrong until a car arrived somewhere
  # else. Report it and let a human adjudicate; GEOCODE_FORCE=1 to override.
  if moved && moved > MAX_DRIFT && ENV['GEOCODE_FORCE'] != '1'
    missed << [location.name, format('would move %dm — check it, then GEOCODE_FORCE=1', moved.round)]
    next
  end

  location.update!(lat: lat, lon: lon)
  updated += 1
  puts format('  %-32s %.5f, %.5f%s', location.name, lat, lon,
              moved ? " (moved #{moved.round}m)" : '')
end

puts
puts "updated #{updated} of #{scope.size}"
return if missed.empty?

puts "#{missed.size} left unchanged:"
missed.each { |name, reason| puts "  #{name} — #{reason}" }
