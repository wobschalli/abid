require_relative 'test_helper'

class LocationTest < AbidTest
  # Adding a sixth zone and forgetting its abbreviation would not raise — it
  # would render as three uppercase letters via the fallback in
  # Location.zone_short and nobody would notice.
  def test_every_zone_has_an_abbreviation
    assert_equal Location::ZONES.sort, Location::ZONE_SHORT.keys.sort
  end

  def test_zone_aliases_all_point_at_a_real_zone
    Location::ZONE_ALIASES.each_value do |zone|
      assert_includes Location::ZONES, zone, "alias points at unknown zone #{zone.inspect}"
    end
  end

  # --- canonical_zone -------------------------------------------------------

  def test_a_canonical_zone_passes_through
    Location::ZONES.each { |zone| assert_equal zone, Location.canonical_zone(zone) }
  end

  def test_case_and_whitespace_are_forgiven
    assert_equal 'Chauncey', Location.canonical_zone('  chauncey ')
    assert_equal 'On-campus', Location.canonical_zone('ON-CAMPUS')
  end

  # The names this list used before migration 2600, so a row written by an old
  # process still lands somewhere sensible.
  def test_legacy_placeholder_names_map_forward
    assert_equal 'On-campus', Location.canonical_zone('Campus')
    assert_equal 'Chauncey', Location.canonical_zone('Downtown')
    assert_equal 'Northwestern', Location.canonical_zone('North')
    assert_equal 'Lafayette', Location.canonical_zone('East')
  end

  def test_common_spellings_map
    assert_equal 'Chauncey', Location.canonical_zone('chauncy')
    assert_equal 'On-campus', Location.canonical_zone('dorms')
    assert_equal 'Chauncey', Location.canonical_zone('the village')
  end

  # Blanking a coordinator's typo destroys the only clue about where that
  # person lives.
  def test_unknown_input_survives_unchanged
    assert_equal 'Atlantis', Location.canonical_zone('Atlantis')
  end

  def test_blank_becomes_nil
    assert_nil Location.canonical_zone(nil)
    assert_nil Location.canonical_zone('')
    assert_nil Location.canonical_zone('   ')
  end

  # --- validation -----------------------------------------------------------

  def test_a_new_location_normalises_its_zone_on_save
    location = Location.create!(name: 'somewhere', zone: 'campus')

    assert_equal 'On-campus', location.zone
  end

  def test_an_unrecognised_zone_is_rejected
    location = Location.new(name: 'nowhere', zone: 'Atlantis')

    refute location.valid?
    assert_includes location.errors[:zone].to_sentence, 'included'
  end

  def test_a_blank_zone_is_allowed
    assert Location.new(name: 'unzoned place').valid?
  end

  # The gate exists so one legacy row cannot roll back an entire AutoFiller
  # transaction. A stale row stays saveable for everything except its zone.
  def test_a_row_with_a_legacy_zone_stays_saveable
    location = Location.create!(name: 'stale place')
    location.update_column(:zone, 'Atlantis')

    location.reload.name = 'renamed'
    assert location.save, 'a stale zone blocked an unrelated update'
  end

  # --- search ---------------------------------------------------------------

  def test_search_by_name_is_case_insensitive
    Location.create!(name: 'cary quadrangle', zone: 'On-campus')

    assert_equal 'cary quadrangle', Location.search_by_name('Cary Quadrangle').first&.name
    assert_equal 'cary quadrangle', Location.search_by_name('  CARY QUADRANGLE ').first&.name
  end

  # Without this the whole aliases mechanism is unreachable and typed pickups
  # geocode a duplicate row instead of finding the seeded one.
  def test_search_by_name_matches_aliases_case_insensitively
    Location.create!(name: 'cary quadrangle', zone: 'On-campus',
                     aliases: ['cary', 'cary quad'])

    assert_equal 'cary quadrangle', Location.search_by_name('Cary Quad').first&.name
    assert_equal 'cary quadrangle', Location.search_by_name('cary').first&.name
  end

  def test_search_by_name_misses_cleanly
    assert_nil Location.search_by_name('nothing like this').first
  end
end
