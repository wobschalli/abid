# Verify every location against the geocoder and record how well it resolved.
#
#   rake db:verify_locations            # places not yet verified
#   GEOCODE_ALL=1 rake db:verify_locations   # re-check everything
#   rake db:geocode                     # the old name, same task
#
# Google Geocoding first (it knows apartment brands and grades its own
# precision), Nominatim as the free fallback — see map/map.rb. Nominatim's
# policy is one request per second, so this stays deliberately slow and
# deliberately not part of seeding: a seed that depends on a third party is
# non-deterministic and fails on a plane.
#
# Nothing is written unless the result lands inside Tippecanoe County — the
# geocoder enforces that itself now — and a big move is reported rather than
# applied, because a plausible wrong pin is the worst outcome: nothing looks
# wrong until a car arrives somewhere else.
require_relative '../config/environment'

Abid.establish_connection
Abid.load_models
# After load_models: map/map.rb requires models/location.rb, which subclasses
# ApplicationRecord and blows up if it is loaded first.
require_relative '../map/map'

PAUSE = 1.1
# Roughly two blocks. Wide enough that a genuine refinement — the eyeballed
# seed coordinates were good to about a block — passes without fuss, tight
# enough that landing on the wrong road does not. A verified rooftop hit is
# trusted further (see below): the whole point of verification is that Google
# saying "this building" beats a number somebody once eyeballed.
MAX_DRIFT = 500
ROOFTOP_DRIFT = 3_000

map = Map.new
scope = if ENV['GEOCODE_ALL'] == '1'
          Location.all
        else
          Location.where(verification: 'unverified').or(Location.where(lat: nil))
        end
scope = scope.order(:name).to_a

if scope.empty?
  puts 'Every location is verified. Use GEOCODE_ALL=1 to re-check them.'
  exit
end

puts "verifying #{scope.size} locations (about #{(scope.size * PAUSE).round}s)…"
puts format('  %-34s %-12s %-44s %s', 'place', 'state', 'address', 'moved')

updated = 0
missed = []

scope.each do |location|
  # Address first: a street is a map feature, a leasing brand is not. The city
  # comes from the location's own zone rather than being hardcoded — Lafayette
  # is across the river from West Lafayette and has its own State Street.
  result = map.geocode(location.geocode_query)
  sleep PAUSE

  if result[:lat].blank?
    missed << [location.name, location.address.present? ? 'no result' : 'no result — needs a street address']
    next
  end

  lat = result[:lat]
  lon = result[:lon]
  moved = if location.coords?
            Math.sqrt(((location.lat.to_f - lat)**2) + ((location.lon.to_f - lon)**2)) * 111_000
          end
  verified = Location::VERIFIED.include?(result[:verification])

  # A big jump is not a refinement, it is a different place — the church
  # proved it: "3501 W 250 N" forward-geocodes onto "3501 N 250 W", 2.8km away
  # and still inside the county. A rooftop match is allowed a longer leash,
  # because that is exactly the case where the old pin was the wrong one:
  # "Village West" sat on a demolished complex 2.7km from the real building.
  # Beyond that, or for any unverified result, report it; GEOCODE_FORCE=1
  # overrides once a human has looked.
  leash = verified ? ROOFTOP_DRIFT : MAX_DRIFT
  if moved && moved > leash && ENV['GEOCODE_FORCE'] != '1'
    missed << [location.name, format('would move %dm (%s) — check it, then GEOCODE_FORCE=1', moved.round, result[:verification])]
    next
  end

  attrs = { lat: lat, lon: lon, verification: result[:verification],
            verified_at: Time.zone.now, place_id: result[:place_id] }
  attrs[:address] = result[:address] if result[:address].present? && verified
  location.update!(attrs)
  updated += 1
  puts format('  %-34s %-12s %-44s %s', location.name[0, 34], result[:verification],
              (attrs[:address] || location.address).to_s[0, 44],
              moved ? "#{moved.round}m" : 'new')
end

puts
puts "updated #{updated} of #{scope.size}"
return if missed.empty?

puts "#{missed.size} left unchanged:"
missed.each { |name, reason| puts "  #{name} — #{reason}" }
