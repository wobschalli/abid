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
CONTEXT = 'West Lafayette, Indiana'.freeze

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
  # Address first: a street is a map feature, a leasing brand is not.
  query = location.geocode_query(CONTEXT)
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
