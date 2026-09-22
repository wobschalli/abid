require_relative 'test_helper'

# The census answered "where do you live" 57 different ways for maybe 30
# places. Every row here is a spelling somebody actually typed; the test is
# that they all land on the one string the seed knows.
class LocationVocabularyTest < AbidTest
  def norm(text) = Location.normalize_term(text)

  def test_the_census_spellings_collapse
    {
      'Lark' => 'lark', 'lark' => 'lark', 'Lark apartments' => 'lark', 'Lark Apts.' => 'lark',
      'Village West' => 'village west', 'village west' => 'village west', 'Village west' => 'village west',
      '3rd and West' => 'third and west', 'third and west' => 'third and west',
      '3rd & West' => 'third and west', '3rd and west' => 'third and west',
      'Rise on Chauncey' => 'rise on chauncey', 'RISE on Chauncey' => 'rise on chauncey',
      'The Rise' => 'rise',
      'Aspire' => 'aspire', 'Aspire apartments' => 'aspire',
      'Continuum Apts.' => 'continuum', 'Provenance apt' => 'provenance',
      'Owen Hall' => 'owen', 'Windsor Halls' => 'windsor', 'Earhart Hall' => 'earhart',
      'Hawkins Hall' => 'hawkins', 'Tarkington dorm room' => 'tarkington dorm room',
      'Meredith South' => 'meredith south', 'Cary Quad' => 'cary quad'
    }.each do |typed, expected|
      assert_equal expected, norm(typed), "#{typed.inspect} normalised wrong"
    end
  end

  def test_a_noise_word_alone_is_not_erased
    # "hall" on its own has to survive, or a place literally called Hall would
    # vanish; only a TRAILING noise word after a real name is dropped.
    assert_equal 'hall', norm('Hall')
    assert_equal 'apartments', norm('apartments')
  end

  def test_search_by_name_finds_every_spelling_of_one_place
    place = Location.create!(name: 'Village West', zone: ZONE_1,
                             aliases: ['village west', 'village west apartments'])

    ['Village West', 'VILLAGE WEST', 'village west apts', 'Village West Apartments'].each do |typed|
      assert_equal place, Location.search_by_name(typed).first, "#{typed.inspect} did not resolve"
    end
  end

  def test_exact_match_still_wins_over_normalised_neighbours
    exact = Location.create!(name: 'Meredith Hall', zone: ZONE_1, aliases: ['meredith'])
    Location.create!(name: 'Meredith South', zone: ZONE_1, aliases: ['meredith south'])

    assert_equal exact, Location.search_by_name('meredith').first
  end

  def test_search_returns_nothing_for_nonsense
    assert_empty Location.search_by_name('!!!')
    assert_empty Location.search_by_name('')
  end

  def test_verification_states_are_constrained
    place = Location.new(name: 'x', zone: ZONE_1, verification: 'guessed')
    refute place.valid?

    place.verification = 'rooftop'
    assert place.valid?
    assert place.verified?

    place.verification = 'approximate'
    refute place.verified?
  end
end
