require 'http'
require 'json'

require_relative File.join('..', 'models', 'location.rb')

class Map
  attr_accessor :box
  BOXES = {
    tippecanoe: %w( -87.0955 40.2143 -86.6948 40.5630 ),
    indiana: %w( -88.102 37.760 -84.798 41.761 )
  }
  # This used to go through the open_street_map gem, whose only real job here
  # was two JSON GETs. That gem depends on libxml-ruby, a native extension that
  # needs libxml2 headers and breaks outright when a conda xml2-config shadows
  # the system one. Not worth it for two requests.
  NOMINATIM_URL = "https://nominatim.openstreetmap.org"

  # Nominatim's usage policy requires an identifying User-Agent.
  USER_AGENT = "abid-rides (https://github.com/wobschalli/abid)"

  private_constant :NOMINATIM_URL, :USER_AGENT

  GOOGLE_URL = "https://maps.googleapis.com/maps/api/geocode/json"
  private_constant :GOOGLE_URL

  # Google's location_type, folded to the four states a coordinator can act
  # on. ROOFTOP is the building; RANGE_INTERPOLATED is a house number placed
  # along the street, good to a few metres; the other two are "somewhere in
  # this area", which must not be shown as a pin anyone can drive to.
  VERIFICATION = {
    'ROOFTOP' => 'rooftop',
    'RANGE_INTERPOLATED' => 'interpolated',
    'GEOMETRIC_CENTER' => 'approximate',
    'APPROXIMATE' => 'approximate'
  }.freeze

  # `api_key: nil` means NO key, on purpose — it is how tests guarantee they
  # never speak to Google. Only an omitted argument reaches for the configured
  # one (the same convention as Rides::TravelMatrix, learned the hard way
  # when a `||` let the suite spend live quota).
  #
  # @param box [Array] bounding box for lookups, BOXES[:tippecanoe] by default
  def initialize(box = BOXES[:tippecanoe], api_key: :configured)
    @box = box
    @api_key = api_key == :configured ? Abid.google_maps_key : api_key
  end

  # @param addr [String] address or name of location
  # @return lat and lon [Hash] — the original contract, kept for every caller
  def addr_to_coord(addr)
    result = geocode(addr)
    { lat: result[:lat], lon: result[:lon] }
  end

  # The full answer, tiered: Google first, Nominatim second, nothing third.
  #
  # Google is first because it knows leasing brands — "Village West", "Lark",
  # "Third and West" — which OpenStreetMap does not, and it says HOW precisely
  # it matched. Nominatim stays as the free fallback so that with no key the
  # app behaves exactly as it did before. A result outside the bounding box is
  # a miss, not an answer: a Lark in Nevada is worse than no Lark at all.
  #
  # @return [Hash] lat, lon, address (formatted, Google only), place_id (Google
  #   only), verification (rooftop/interpolated/approximate/unverified),
  #   source (:google, :nominatim, nil)
  def geocode(query)
    return miss if query.to_s.strip.empty?

    google(query) || nominatim(query) || miss
  end

  # @param coord [Hash] hash with lon and lat
  # @return name [String]
  def coord_to_addr(coord)
    response = get("#{NOMINATIM_URL}/reverse", {
      format: 'json', lon: coord[:lon], lat: coord[:lat]
    })
    response.is_a?(Hash) ? response['display_name'] : nil
  end

  # `create_trip`, `create_route` and `suggest_path` lived here. All three were
  # called by nothing, and create_trip was broken for real data anyway: its
  # `places.map(&:sort).map(&:reverse).map { |p| p.flatten.keep_if { String } }`
  # kept the hash KEYS and dropped the BigDecimal values, producing a URL like
  # ".../driving/;;". create_route's `.pop(n - 1)` silently discarded the
  # origin. They also used bare HTTP.get with no timeout or error handling.
  #
  # Pickup ordering and the maps link now live in services/route_planner.rb,
  # which needs no route optimiser at all.

  # @param location data, either a hash with lon, lat or a string [Hash, String]
  # @return [Location, nil]
  def create_new_location(data)
    case data.class.to_s
    when "String"
      return nil if data.empty?
      coords = addr_to_coord(data).delete_if { |_, v| v.nil? }
      unless coords.empty?
        # The typed text is an ADDRESS, and goes in the address column. Storing
        # it as the name made every one-off pickup spot a permanent place in the
        # Locations list called "1838 King Eider Drive", with no zone.
        return Location.create(coords.merge({ name: data, address: data }))
      end
      nil
    when "Hash"
      return nil unless data[:lon] && data[:lat]
      name = coord_to_addr(data)
      unless name.nil? || name.empty?
        return Location.create(data.merge({ name: name }))
      end
      nil
    else
      nil
    end
  end

  private

  def miss
    { lat: nil, lon: nil, address: nil, place_id: nil, verification: 'unverified', source: nil }
  end

  def google(query)
    return nil if @api_key.nil?

    response = get(GOOGLE_URL, {
      address: query, components: 'country:US|administrative_area:IN', key: @api_key
    })
    return nil unless response.is_a?(Hash) && response['status'] == 'OK'

    place = response['results'].to_a.first or return nil
    loc = place.dig('geometry', 'location') or return nil
    lat = loc['lat'].to_f
    lon = loc['lng'].to_f
    return nil unless inside_box?(lat, lon)

    verification = VERIFICATION.fetch(place.dig('geometry', 'location_type').to_s, 'approximate')
    # A partial match is Google saying "I could not find exactly this, here is
    # my best guess". At rooftop precision that guess is still a real building
    # — the brand-name lookups all come back this way — so only a partial that
    # is ALSO imprecise is downgraded.
    verification = 'approximate' if place['partial_match'] && verification != 'rooftop'

    { lat: lat, lon: lon, address: place['formatted_address'], place_id: place['place_id'],
      verification: verification, source: :google }
  end

  def nominatim(query)
    response = get("#{NOMINATIM_URL}/search", {
      q: query, format: 'json', viewbox: q_box, bounded: 1, limit: 1
    })
    place = response.is_a?(Array) ? response.first : nil
    return nil if place.nil?

    # Nominatim is bounded by the viewbox already; it does not grade its own
    # precision, so the honest label is "somewhere near this", never rooftop.
    { lat: place['lat'].to_f, lon: place['lon'].to_f, address: nil, place_id: nil,
      verification: 'approximate', source: :nominatim }
  end

  # BOXES are lon_min, lat_min, lon_max, lat_max.
  def inside_box?(lat, lon)
    lon_min, lat_min, lon_max, lat_max = @box.map(&:to_f)
    lat.between?(lat_min, lat_max) && lon.between?(lon_min, lon_max)
  end

  # Returns parsed JSON, or nil if the service is unreachable or answers with
  # anything other than a 2xx. Callers treat nil as "no result".
  def get(url, params)
    response = HTTP.headers(accept: 'application/json', user_agent: USER_AGENT)
                   .timeout(connect: 5, read: 10)
                   .get(url, params: params)
    return nil unless response.status.success?

    JSON.parse(response.body.to_s)
  rescue HTTP::Error, JSON::ParserError => e
    warn "OSM lookup failed (#{url}): #{e.class}: #{e.message}"
    nil
  end

  def q_box
    @box.join ','
  end
end
