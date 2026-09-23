require 'http'
require 'json'

module Rides
  # Driving seconds between locations, for the optimizer.
  #
  # Three tiers, in order:
  #   1. the travel_times cache — permanent, deterministic, free
  #   2. the Google Distance Matrix, batch-fetched only for pairs never seen,
  #      then cached forever (no departure_time: typical driving, not traffic,
  #      because numbers that drift between runs would keep asking to move
  #      people that frozen rides forbid moving)
  #   3. haversine × a road-detour factor at city speed — used when there is no
  #      key, when Google fails, and for places that only have a zone
  #
  # The estimate tier is why none of this can strand a Sunday morning: with no
  # key and no network the optimizer still runs, just on straight-line time.
  class TravelMatrix
    # West Lafayette streets are a grid interrupted by a river; 1.3 is the
    # usual detour factor for that shape of town.
    DETOUR = 1.3
    CITY_SPEED_KMH = 30.0
    EARTH_KM = 6371.0
    # Google enforces two caps per request: 100 elements total AND 25 per
    # dimension. With one origin per request the binding one is 25
    # destinations — 41 in one call comes back MAX_DIMENSIONS_EXCEEDED, which
    # is how this number was learned.
    MAX_DESTINATIONS = 25

    Point = Struct.new(:location_id, :lat, :lon, keyword_init: true)

    # `api_key: nil` means NO key, on purpose — it is how tests guarantee they
    # never speak to Google. Only an omitted argument reaches for the real one;
    # an `||` here once let the suite pick up the production key from
    # config.yml and spend live quota from inside a unit test.
    def initialize(api_key: :configured)
      @api_key = api_key == :configured ? Abid.google_maps_key : api_key
      @cache = {}
    end

    # Resolve a Ride (or anything with #pickup) / Location to a Point.
    #
    # A place with no coordinates borrows its ZONE's centroid — degraded
    # precision beats exclusion, since a rider the matrix cannot see is a rider
    # the optimizer silently leaves in the pool. nil only when there is
    # genuinely nothing to go on.
    def point_for(subject)
      location = subject.is_a?(Location) ? subject : subject.pickup
      if location&.coords?
        return Point.new(location_id: location.id, lat: location.lat.to_f, lon: location.lon.to_f)
      end

      zone = location&.zone || (subject.respond_to?(:zone) ? subject.zone : nil)
      centroid = zone_centroid(zone)
      return nil if centroid.nil?

      # No location_id: a centroid is not a cacheable pair endpoint, so these
      # always go through the estimate tier.
      Point.new(location_id: nil, lat: centroid[0], lon: centroid[1])
    end

    # Seconds from a to b. Never raises, never blocks on the network beyond the
    # one batch fetch below; a lone uncached pair mid-solve estimates.
    def seconds(a, b)
      return 0 if a.nil? || b.nil?
      return 0 if a.location_id && a.location_id == b.location_id

      cached(a, b) || estimate(a, b)
    end

    # Fetch-and-cache every unknown pair among `points` in one pass, BEFORE the
    # solve, so `seconds` is pure lookup during it. Failures degrade to
    # estimates for this run and are retried next time (nothing is cached as
    # 'google' unless Google actually said it).
    def warm(points)
      ids = points.filter_map(&:location_id).uniq
      return if ids.size < 2

      known = TravelTime.where(from_location_id: ids, to_location_id: ids)
                        .pluck(:from_location_id, :to_location_id).to_set
      missing = ids.product(ids).reject { |f, t| f == t || known.include?([f, t]) }
      return if missing.empty?

      preload(ids)
      return if @api_key.nil?

      fetch_pairs(missing)
      preload(ids)
    rescue StandardError => e
      warn "travel matrix warm failed (estimating this run): #{e.class}: #{e.message}"
    end

    private

    def preload(ids)
      TravelTime.where(from_location_id: ids, to_location_id: ids).find_each do |row|
        @cache[[row.from_location_id, row.to_location_id]] = row.seconds
      end
    end

    def cached(a, b)
      return nil if a.location_id.nil? || b.location_id.nil?

      @cache[[a.location_id, b.location_id]]
    end

    def estimate(a, b)
      km = haversine_km(a.lat, a.lon, b.lat, b.lon)
      ((km * DETOUR) / CITY_SPEED_KMH * 3600).round
    end

    def haversine_km(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180
      dlat = (lat2 - lat1) * rad
      dlon = (lon2 - lon1) * rad
      h = Math.sin(dlat / 2)**2 +
          (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlon / 2)**2)
      2 * EARTH_KM * Math.asin(Math.sqrt(h))
    end

    def zone_centroid(zone)
      return nil if zone.blank?

      @centroids ||= {}
      @centroids[zone] ||= begin
        rows = Location.in_zone(zone).where.not(lat: nil).pluck(:lat, :lon)
        rows.empty? ? nil : [rows.sum { |r| r[0].to_f } / rows.size,
                             rows.sum { |r| r[1].to_f } / rows.size]
      end
    end

    # --- the one place that talks to Google ---------------------------------

    def fetch_pairs(pairs)
      coords = Location.where(id: pairs.flatten.uniq).where.not(lat: nil)
                       .to_h { |l| [l.id, [l.lat.to_f, l.lon.to_f]] }
      pairs = pairs.select { |f, t| coords[f] && coords[t] }

      # One request per origin keeps every batch well under the element cap and
      # the URL length limit; ~30 locations is ~30 requests, once ever.
      pairs.group_by(&:first).each do |from_id, group|
        dest_ids = group.map(&:last)
        dest_ids.each_slice(MAX_DESTINATIONS) do |slice|
          fetch_row(from_id, slice, coords)
        end
      end
    end

    def fetch_row(from_id, dest_ids, coords)
      origin = coords[from_id].join(',')
      destinations = dest_ids.map { |id| coords[id].join(',') }.join('|')

      response = HTTP.timeout(10).get(
        'https://maps.googleapis.com/maps/api/distancematrix/json',
        params: { origins: origin, destinations: destinations,
                  mode: 'driving', key: @api_key }
      )
      body = JSON.parse(response.body.to_s)
      unless body['status'] == 'OK'
        warn "distance matrix refused: #{body['status']} #{body['error_message']}"
        return
      end

      elements = body.dig('rows', 0, 'elements') || []
      dest_ids.zip(elements).each do |to_id, element|
        next unless element&.dig('status') == 'OK'

        store(from_id, to_id, element.dig('duration', 'value').to_i, 'google')
      end
    rescue StandardError => e
      warn "distance matrix fetch failed for location #{from_id}: #{e.class}: #{e.message}"
    end

    def store(from_id, to_id, seconds, source)
      TravelTime.create!(from_location_id: from_id, to_location_id: to_id,
                         seconds: seconds, source: source)
    rescue ActiveRecord::RecordNotUnique
      # Two processes warmed the same pair; the first writer wins.
    end
  end
end
