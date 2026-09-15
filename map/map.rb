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

  # @param box [Symbol] binding box for OSM lookups, either indiana or tippecanoe
  def initialize(box=BOXES[:tippecanoe])
    @box = box
  end

  # @param addr [String] address or name of location
  # @return lat and lon [Hash]
  def addr_to_coord(addr)
    response = get("#{NOMINATIM_URL}/search", {
      q: addr, format: 'json', viewbox: q_box, bounded: 1, limit: 1
    })
    place = response.is_a?(Array) ? response.first : nil
    return { lat: nil, lon: nil } if place.nil?

    { lat: place['lat'], lon: place['lon'] }
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
        return Location.create(coords.merge({ name: data }))
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

  # Returns parsed JSON, or nil if OSM is unreachable or answers with anything
  # other than a 2xx. Callers treat nil as "no result".
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
