require_relative 'test_helper'

# The matrix's job is to be boring: cached pairs come back identical forever,
# nothing here ever raises, and with no API key the whole thing runs on
# estimates. No test in this file touches the network.
class TravelMatrixTest < AbidTest
  def setup
    super
    @a = Location.create!(name: 'a', zone: ZONE_1, lat: 40.4300, lon: -86.9100)
    @b = Location.create!(name: 'b', zone: ZONE_1, lat: 40.4500, lon: -86.9700)
  end

  def matrix
    Rides::TravelMatrix.new(api_key: nil)
  end

  def test_a_cached_pair_is_used_verbatim
    TravelTime.create!(from_location: @a, to_location: @b, seconds: 424, source: 'google')

    m = matrix
    m.warm([m.point_for(@a), m.point_for(@b)])

    assert_equal 424, m.seconds(m.point_for(@a), m.point_for(@b))
  end

  def test_no_key_means_estimates_and_no_crash
    m = matrix
    m.warm([m.point_for(@a), m.point_for(@b)])

    seconds = m.seconds(m.point_for(@a), m.point_for(@b))
    # ~5.5km straight line, ×1.3 detour, at 30km/h → in the several-minutes
    # range. The exact number matters less than it being sane and repeatable.
    assert_operator seconds, :>, 300
    assert_operator seconds, :<, 2000
    assert_equal seconds, m.seconds(m.point_for(@a), m.point_for(@b))
    assert_equal 0, TravelTime.count, 'estimates must not be cached as truth'
  end

  def test_same_place_costs_nothing
    m = matrix
    assert_equal 0, m.seconds(m.point_for(@a), m.point_for(@a))
  end

  def test_a_coordless_location_borrows_its_zone_centroid
    fuzzy = Location.create!(name: 'somewhere', zone: ZONE_1)

    point = matrix.point_for(fuzzy)

    refute_nil point, 'a zoned location must be placeable'
    assert_nil point.location_id, 'a centroid is not a cacheable endpoint'
    assert_in_delta 40.44, point.lat, 0.02
  end

  def test_moving_a_location_forgets_its_cached_times
    TravelTime.create!(from_location: @a, to_location: @b, seconds: 424, source: 'google')
    TravelTime.create!(from_location: @b, to_location: @a, seconds: 431, source: 'google')

    @a.update!(lat: 40.5)

    assert_equal 0, TravelTime.count,
                 'a moved pin left times to a place that no longer exists'
  end
end
