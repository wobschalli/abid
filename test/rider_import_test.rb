require_relative 'test_helper'

# A wrong match here attaches one student's phone number and home address to
# another student's account, and nothing downstream would flag it — the board
# would simply start sending a driver to the wrong building. These tests are
# mostly about the cases where the importer must REFUSE to guess.
class RiderImportTest < AbidTest
  def setup
    super
    @home = Location.create!(name: 'Cary Quadrangle', zone: Location::ZONES.first,
                             aliases: ['cary', 'cary quad', 'cary nw'])
  end

  def make_user(name:, username:, **attrs)
    User.create!(name: name, username: username, discord_id: next_discord_id,
                 password: 'x' * 10, **attrs)
  end

  def row(**attrs) = RiderImport::Row.new(**attrs)

  # NOT `Array(rows)` — a Struct responds to to_a, so that splatted a single Row
  # into its own field values.
  def import(rows, **opts) = RiderImport.new(rows.is_a?(Array) ? rows : [rows], **opts).call

  # The Members page offers Drivers and Riders as tabs, so between them they
  # have to account for everybody — nobody may be in neither or in both.
  def test_riders_is_the_exact_complement_of_drivers
    make_user(name: 'Has a car', username: 'driver1', capacity: 4)
    make_user(name: 'No car', username: 'rider1')
    make_user(name: 'Zero seats', username: 'rider2', capacity: 0)

    assert_equal User.count, User.drivers.count + User.riders.count
    assert_empty User.drivers.where(id: User.riders), 'nobody may be both'
  end

  def test_matches_on_exact_discord_username
    user = make_user(name: 'Marcus Ito', username: 'marcusito23')

    result = import(row(name: 'Marcus Ito', handle: 'marcusito23', phone: '7651234567')).first

    assert_equal user, result.user
    assert_equal :username, result.how
    assert_equal '7651234567', user.reload.phone
  end

  def test_matches_when_the_written_handle_is_really_a_display_name
    # People write down what they see in the member list, which is the display
    # name, not the username.
    user = make_user(name: 'Codyna', username: 'bouncyjello')

    result = import(row(name: 'Cody na', handle: 'Codyna')).first

    assert_equal user, result.user
    assert_equal :display_name, result.how
  end

  def test_matches_across_the_punctuation_discord_allows
    # 'TheOscar' on paper, '_theoscar' in Discord. Stripping . and _ is a real
    # normalisation of the handle format, not a fuzzy guess.
    user = make_user(name: 'The Oscar', username: '_theoscar')

    result = import(row(name: 'Oscar Shane', handle: 'TheOscar')).first

    assert_equal user, result.user
    assert_equal :relaxed, result.how
  end

  def test_refuses_to_match_a_handle_that_is_merely_a_substring
    # 'wob' vs '@wibblewobblebobble'. Substring matching would claim this one,
    # and it is a different person.
    make_user(name: 'Bobby', username: 'wibblewobblebobble')

    result = import(row(name: 'Jonas Lim', handle: 'wob')).first

    assert_nil result.user
    assert_equal :unmatched, result.how
  end

  def test_refuses_when_one_name_claims_two_people
    # Three accounts have the display name 'nate'. Matching any of them is a
    # coin flip, so the importer must match none and report it.
    make_user(name: 'nate', username: 'marcusito23')
    make_user(name: 'nate', username: 'demarcateded')

    result = import(row(name: 'Marcus Ito', handle: 'nate', phone: '7650000000')).first

    assert_nil result.user, 'an ambiguous display name must not resolve to an arbitrary account'
    assert_equal :unmatched, result.how
  end

  def test_matches_a_first_name_plus_initial_display_name
    # Discord shows 'Casey F.'; the roster says 'Casey Flynn'.
    user = make_user(name: 'Casey F.', username: 'fernley7838')
    make_user(name: 'Casey M.', username: 'moxie4461')
    make_user(name: 'Casey P.', username: 'cp_op')

    result = import(row(name: 'Casey Flynn', phone: '7654445555')).first

    assert_equal user, result.user
    assert_equal :name_initial, result.how
  end

  def test_matches_a_first_name_only_display_name_when_unique
    user = make_user(name: 'Ranbir', username: 'ranbirsu')

    result = import(row(name: 'Ranbir Atwal', capacity: 6)).first

    assert_equal user, result.user
    assert_equal :first_name, result.how
    assert_equal 6, user.reload.capacity
  end

  def test_refuses_a_first_name_two_different_people_claim
    # One Discord 'Bella'; the roster has Bella Cho and Bella Liu. Nothing here
    # can say which, so neither may claim her.
    bella = make_user(name: 'Bella', username: 'bellaonly')

    results = import([row(name: 'Bella Cho', phone: '7650001111'),
                      row(name: 'Bella Liu', phone: '7650002222')])

    assert(results.none?(&:matched?), 'a contested first name must match nobody')
    assert_equal [:ambiguous_name], results.map(&:problem).uniq
    assert_nil bella.reload.phone
  end

  def test_never_creates_a_user
    before = User.count
    import(row(name: 'Nobody At All', handle: 'ghost', phone: '7650000000'))

    assert_equal before, User.count
  end

  def test_does_not_overwrite_details_the_person_already_set
    # A value in the dashboard is more current than a spreadsheet row.
    other = Location.create!(name: 'Wiley Hall', zone: Location::ZONES.first, aliases: ['wiley'])
    user = make_user(name: 'Tim Lee', username: 'tacotimmy',
                     phone: '7659999999', location: other, capacity: 5)

    import(row(name: 'Tim Lee', handle: 'tacotimmy', phone: '7651111111',
               residence: 'cary', capacity: 4))

    user.reload
    assert_equal '7659999999', user.phone
    assert_equal other, user.location
    assert_equal 5, user.capacity
  end

  def test_resolves_a_residence_through_its_alias
    user = make_user(name: 'Sebastian Ting', username: 'white.elephant')

    result = import(row(name: 'Sebastian Ting', handle: 'white.elephant', residence: 'cary quad')).first

    assert_equal @home, user.reload.location
    assert_equal :exact, result.residence_match
  end

  def test_finds_the_building_inside_a_noisy_free_text_answer
    # Real answers: 'Earhart 267', 'Apt lark', 'Dorm - Meredith South'.
    user = make_user(name: 'Renata Yung', username: 'skrillyxxx')

    result = import(row(name: 'Renata Yung', handle: 'skrillyxxx', residence: 'Dorm - Cary NW 267')).first

    assert_equal @home, user.reload.location
    assert_equal :partial, result.residence_match
  end

  def test_reports_an_unknown_residence_rather_than_inventing_one
    user = make_user(name: 'David Zhang', username: 'bloonsaddict')

    before = Location.count
    result = import(row(name: 'David Zhang', handle: 'bloonsaddict', residence: "Caleb's House")).first

    assert_equal before, Location.count, 'a free-text answer must not become a zoneless Location row'
    assert_nil result.residence_match
    assert_nil user.reload.location
  end

  def test_dry_run_writes_nothing_but_still_reports_what_it_would_do
    user = make_user(name: 'Nathan Wu', username: 'wuna')

    result = import(row(name: 'Nathan Wu', handle: 'WUNA', phone: '7652223333',
                        residence: 'cary'), dry_run: true).first

    assert_equal user, result.user
    assert_equal '7652223333', result.changes[:phone], 'dry run must still report the change'
    assert_nil user.reload.phone, 'dry run must not write'
  end
end
