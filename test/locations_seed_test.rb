require_relative 'test_helper'
require_relative '../db/locations'

# The seed is run against a live database with people already pointing at
# rows. Two promises matter more than the list being complete: a rename keeps
# the row (and every users.location_id on it), and a seed run never takes an
# alias away.
class LocationsSeedTest < AbidTest
  def test_a_rename_keeps_the_row_and_everyone_pointing_at_it
    stale = Location.create!(name: 'Purdue Village', zone: ZONE_1, lat: 40.4310, lon: -86.9280,
                             aliases: ['village west', 'nimitz'])
    resident = User.create!(name: 'Resident', username: "res#{next_discord_id}", discord_id: next_discord_id,
                            password: 'x' * 10, location: stale)

    Abid::Locations.seed!

    renamed = Location.find(stale.id)
    assert_equal 'Village West', renamed.name
    assert_equal stale.id, resident.reload.location_id, 'the resident was orphaned by the rename'
    assert_nil Location.find_by(name: 'Purdue Village'), 'the stale name survived beside the new one'
    assert_includes renamed.aliases, 'purdue village', 'the old name must still resolve'
    assert_includes renamed.aliases, 'nimitz', 'an existing alias was dropped'
    assert_equal 'unverified', renamed.verification, 'a renamed pin must be re-verified, not trusted'
  end

  def test_a_rename_does_nothing_when_the_new_name_already_exists
    Location.create!(name: 'Village West', zone: ZONE_1)
    stale = Location.create!(name: 'Purdue Village', zone: ZONE_1)

    Abid::Locations.seed!

    assert_equal 'Purdue Village', stale.reload.name, 'renamed onto an existing row'
  end

  def test_seeding_never_removes_an_alias
    place = Location.create!(name: 'lark', zone: ZONE_1, aliases: ['a spelling only the database knows'])

    Abid::Locations.seed!

    assert_includes place.reload.aliases, 'a spelling only the database knows'
  end

  def test_seeding_never_overwrites_a_coordinate
    place = Location.create!(name: 'Cary Quadrangle', zone: ZONE_1, lat: 40.0, lon: -86.0)

    Abid::Locations.seed!

    assert_equal 40.0, place.reload.lat.to_f, 'a hand-corrected pin was overwritten by the seed'
  end
end
