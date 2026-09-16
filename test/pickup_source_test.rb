require_relative 'test_helper'

# Where someone lives and where they are before a Friday event are usually not
# the same place — 42 of the 63 people who told us both gave different answers.
# The event decides which one the board collects from.
class PickupSourceTest < AbidTest
  def setup
    super
    @home = location_in(ZONE_1)
    @class_spot = location_in(ZONE_2)
    @user = make_user('laura')
    @user.update!(location: @home, class_location: @class_spot)
  end

  def ride_on(pickup_source)
    event = make_event
    event.update!(pickup_source: pickup_source)
    event.rides.create!(user: @user, role: 'rider', status: 'requested')
  end

  def test_a_home_event_collects_from_home
    assert_equal @home, ride_on('home').pickup
  end

  def test_a_class_event_collects_from_the_class_location
    assert_equal @class_spot, ride_on('class').pickup
  end

  # Most people never answered the Friday question, and a blank must not mean
  # "collect them from nowhere".
  def test_a_class_event_falls_back_to_home_when_no_class_location_is_known
    @user.update!(class_location: nil)

    assert_equal @home, ride_on('class').pickup
  end

  # The per-occurrence override is what a coordinator types into the details
  # rail; it is about this one week and beats both.
  def test_a_pickup_typed_on_the_ride_beats_either_address
    override = location_in(ZONE_3)
    ride = ride_on('class')
    ride.update!(pickup_location: override)

    assert_equal override, ride.reload.pickup
  end

  def test_the_zone_follows_whichever_address_was_used
    assert_equal ZONE_1, ride_on('home').zone
    assert_equal ZONE_2, ride_on('class').zone
  end

  def test_events_default_to_home
    assert_equal 'home', make_event.pickup_source
  end

  def test_a_series_stamps_its_choice_onto_each_occurrence
    series = EventSeries.create!(name: 'Abide', weekday: 5, start_time_of_day: '18:30',
                                 pickup_source: 'class')

    occurrence = series.ensure_occurrence(Time.zone.today.next_occurring(:friday))

    assert_equal 'class', occurrence.pickup_source
  end

  def test_an_unknown_pickup_source_is_rejected
    event = make_event
    event.pickup_source = 'wherever'

    refute event.valid?
  end
end
