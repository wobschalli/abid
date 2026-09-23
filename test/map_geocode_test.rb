require_relative 'test_helper'
require_relative '../map/map'

# The geocoder is tiered — Google, then Nominatim, then nothing — and grades
# its answer. No test here touches the network: `get` is the one method that
# does, and it is replaced with canned responses per URL.
class MapGeocodeTest < AbidTest
  GOOGLE = 'maps.googleapis.com'.freeze
  OSM = 'nominatim.openstreetmap.org'.freeze

  # Inside Tippecanoe County.
  HERE = { 'lat' => 40.4471, 'lng' => -86.9391 }.freeze

  class CannedMap < Map
    attr_reader :calls

    def initialize(responses, api_key:)
      super(Map::BOXES[:tippecanoe], api_key: api_key)
      @responses = responses
      @calls = []
    end

    private

    def get(url, _params)
      @calls << url
      key = @responses.keys.find { |host| url.include?(host) }
      @responses.fetch(key) { raise "unexpected network call to #{url}" }
    end
  end

  def google_result(location_type:, partial: false, formatted: '2053 Willowbrook Dr, West Lafayette, IN 47906, USA', at: HERE)
    { 'status' => 'OK',
      'results' => [{ 'formatted_address' => formatted, 'place_id' => 'ChIJ-example',
                      'partial_match' => partial,
                      'geometry' => { 'location' => at, 'location_type' => location_type } }] }
  end

  def test_a_rooftop_hit_is_verified_with_googles_address
    map = CannedMap.new({ GOOGLE => google_result(location_type: 'ROOFTOP') }, api_key: 'k')

    r = map.geocode('Village West, West Lafayette, Indiana')

    assert_equal 'rooftop', r[:verification]
    assert_equal :google, r[:source]
    assert_equal 'ChIJ-example', r[:place_id]
    assert_includes r[:address], 'Willowbrook'
    assert_in_delta 40.4471, r[:lat], 0.0001
  end

  # Brand-name lookups come back partial AND rooftop: Google found the
  # building but not the literal string. That is still the building.
  def test_a_partial_rooftop_hit_stays_verified
    map = CannedMap.new({ GOOGLE => google_result(location_type: 'ROOFTOP', partial: true) }, api_key: 'k')

    assert_equal 'rooftop', map.geocode('Lark')[:verification]
  end

  def test_an_imprecise_hit_is_only_approximate
    map = CannedMap.new({ GOOGLE => google_result(location_type: 'GEOMETRIC_CENTER') }, api_key: 'k')

    assert_equal 'approximate', map.geocode('somewhere vague')[:verification]
  end

  def test_a_google_hit_outside_the_county_falls_through_to_nominatim
    nevada = { 'lat' => 36.17, 'lng' => -115.14 }
    map = CannedMap.new({ GOOGLE => google_result(location_type: 'ROOFTOP', at: nevada),
                          OSM => [{ 'lat' => '40.4300', 'lon' => '-86.9100' }] }, api_key: 'k')

    r = map.geocode('Lark')

    assert_equal :nominatim, r[:source], 'a Lark in Nevada was accepted'
    assert_equal 'approximate', r[:verification], 'Nominatim cannot grade precision; never call it verified'
    assert_in_delta 40.43, r[:lat], 0.001
  end

  def test_no_key_never_asks_google
    map = CannedMap.new({ OSM => [{ 'lat' => '40.4300', 'lon' => '-86.9100' }] }, api_key: nil)

    r = map.geocode('Cary Quadrangle, West Lafayette, Indiana')

    assert_equal :nominatim, r[:source]
    refute map.calls.any? { |u| u.include?(GOOGLE) }, 'called Google with no key'
  end

  def test_nothing_anywhere_is_an_honest_miss
    map = CannedMap.new({ GOOGLE => { 'status' => 'ZERO_RESULTS', 'results' => [] }, OSM => [] }, api_key: 'k')

    r = map.geocode('Mechanical Engineering Building, Purdue')

    assert_nil r[:lat]
    assert_equal 'unverified', r[:verification]
    assert_nil r[:source]
  end

  def test_addr_to_coord_keeps_its_old_shape
    map = CannedMap.new({ GOOGLE => google_result(location_type: 'ROOFTOP') }, api_key: 'k')

    assert_equal %i[lat lon], map.addr_to_coord('x').keys
  end

  def test_blank_query_makes_no_request
    map = CannedMap.new({}, api_key: 'k')

    assert_nil map.geocode('   ')[:lat]
    assert_empty map.calls
  end
end
