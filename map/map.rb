require 'open_street_map'
require 'http'

class Map
  attr_accessor :client, :box
  BOXES = {
    tippecanoe: %w( -87.0955 40.2143 -86.6948 40.5630 ),
    indiana: %w( -88.102 37.760 -84.798 41.761 )
  }
  OSRM_TRIP_URL = "http://router.project-osrm.org/trip/v1/driving"
  OSRM_ROUTE_URL = "http://router.project-osrm.org/route/v1/driving"

  private_constant :OSRM_TRIP_URL, :OSRM_ROUTE_URL

  def initialize(box=BOXES[:tippecanoe])
    @client = OpenStreetMap::Client.new
    @box = box
  end

  def addr_to_coord(addr)
    begin
      response = client.search(q: addr, format: 'json', viewbox: q_box, bounded: 1, limit: 1)[0]
      { lat: response['lat'], lon: response['lon'] }
    rescue NoMethodError
      { lat: nil, lon: nil }
    end
  end

  def coord_to_addr(coord)
    response = client.reverse(format: 'json', lon: coord[:lon], lat: coord[:lat])
    response['display_name']
  end

  #takes array of lat/lon hash
  def create_trip(places)
    opts = { source: 'first', destination: 'last', roundtrip: 'false' }
    q_string = "#{OSRM_TRIP_URL}/"
    q_string += places.map(&:sort).map(&:reverse).map{ |place| place.flatten.keep_if{ |e| e.is_a? String }.join(',') }.join(';')
    q_string += '?'
    q_string += opts.map{ |k, v| "#{k}=#{v}"}.join('&')
    response = JSON.parse HTTP.get(q_string)
    response['waypoints'].sort_by{ |place| place['waypoint_index'] }.map{ |place| place['location'] }
  end

  # takes an array of arrays
  def create_route(stops)
    opts = { alternatives: 'true', steps: 'true' }
    q_string = "#{OSRM_ROUTE_URL}/"
    q_string += stops.map{ |stop| stop.join(',') }.join(';')
    q_string += '?'
    q_string += opts.map{ |k, v| "#{k}=#{v}"}.join('&')
    response = JSON.parse HTTP.get(q_string)
    response['waypoints'].map { |stop| stop.to_h['location'] }.pop(response['waypoints'].length - 1)
  end

  def suggest_path(nodes)
    trip = create_trip nodes
    path = create_route trip
    path.map do |stop|
      coord_to_addr({ lon: stop[0], lat: stop[1] })
    end
  end

  private
  def q_box
    @box.join ','
  end
end
