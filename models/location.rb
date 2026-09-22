class Location < ApplicationRecord
  # Pickup areas around Purdue that the board groups and auto-fills by. Ordered
  # the way a driver actually sweeps: campus, then the Village, up Northwestern,
  # west to Klondike, across the river last. RoutePlanner uses this order
  # directly (services/route_planner.rb), so it is not just cosmetic.
  ZONES = %w[On-campus Chauncey Northwestern Klondike Lafayette].freeze

  ZONE_SHORT = {
    'On-campus' => 'CMP',
    'Chauncey' => 'CHY',
    'Northwestern' => 'NW',
    'Klondike' => 'KLD',
    'Lafayette' => 'LAF'
  }.freeze

  # Spellings that should land on a canonical zone: the placeholder names this
  # list used before migration 2600, plus what people actually type. Keep the
  # first four in step with that migration's mapping.
  ZONE_ALIASES = {
    'campus' => 'On-campus',
    'downtown' => 'Chauncey',
    'north' => 'Northwestern',
    'east' => 'Lafayette',
    'on campus' => 'On-campus',
    'oncampus' => 'On-campus',
    'dorm' => 'On-campus',
    'dorms' => 'On-campus',
    'village' => 'Chauncey',
    'the village' => 'Chauncey',
    'chauncy' => 'Chauncey',
    'nw' => 'Northwestern',
    'west lafayette' => 'Northwestern',
    'wl' => 'Northwestern',
    'laf' => 'Lafayette'
  }.freeze

  has_many :events
  has_many :users
  has_many :rides, foreign_key: :pickup_location_id

  # Case-insensitive on both sides. It used to be exact, which made the whole
  # aliases mechanism unreachable: a coordinator typing "Cary Quad" never
  # matched the stored "cary quad", so geocoding created a duplicate row with
  # no zone and no aliases instead of finding the seeded one.
  #
  # The bound parameters matter — this scope previously interpolated a Discord
  # modal value straight into SQL, and a location named `x') OR ('1'='1` was a
  # working injection.
  #
  # Exact (case-folded) first, then the normalised form: "Lark apartments",
  # "RISE on Chauncey" and "3rd & West" are the same places as "lark", "rise
  # on chauncey" and "third and west", and the census proved people type all
  # of them. The normalised pass is a Ruby scan — there are ~90 places, and a
  # SQL expression for "strip trailing 'apartments'" is not worth its
  # unreadability.
  scope :search_by_name, lambda { |name|
    key = name.to_s.strip.downcase
    exact = where('lower(name) = ?', key)
            .or(where('EXISTS (SELECT 1 FROM unnest(aliases) a WHERE lower(a) = ?)', key))
    next exact if exact.exists?

    norm = normalize_term(name)
    next none if norm.blank?

    where(id: all.select { |place| place.terms.any? { |term| normalize_term(term) == norm } }.map(&:id))
  }

  # How sure we are that the pin is the building. Anything but the first two
  # is a guess the Locations page must show as one.
  VERIFICATIONS = %w[rooftop interpolated approximate unverified].freeze
  VERIFIED = %w[rooftop interpolated].freeze
  validates :verification, inclusion: { in: VERIFICATIONS }

  # Words that people bolt onto a place name without changing which place they
  # mean. Stripped from the END only, and repeatedly: "Lark apartments" and
  # "Owen Hall" lose one word; "Windsor Halls dorm" loses two; "South Hall"
  # becomes "south", which is fine because nothing else normalises to that.
  NOISE_SUFFIXES = %w[apartments apartment apts apt halls hall dorm dorms residence residences building bldg].freeze

  ORDINALS = { '1st' => 'first', '2nd' => 'second', '3rd' => 'third', '4th' => 'fourth',
               '5th' => 'fifth', '6th' => 'sixth' }.freeze

  # The spelling-insensitive key for a place name. Deterministic and cheap; the
  # goal is that every way the census spells one building lands on one string.
  def self.normalize_term(text)
    words = text.to_s.downcase
                .gsub('&', ' and ')
                .gsub(/[^a-z0-9\s]/, ' ')
                .split
                .map { |w| ORDINALS.fetch(w, w) }
    words.shift if words.first == 'the'
    words.pop while words.size > 1 && NOISE_SUFFIXES.include?(words.last)
    words.join(' ')
  end

  # Every spelling this place answers to.
  def terms
    [name] + aliases.to_a
  end

  def verified?
    VERIFIED.include?(verification)
  end
  scope :search_by_coords, ->(lat, lon) { where(lon: lon).where(lat: lat) }
  scope :in_zone, ->(zone) { where(zone: zone) }
  scope :zoned, -> { where.not(zone: nil) }

  before_validation :canonicalize_zone
  # Cached driving times are FROM somewhere — move the somewhere and they are
  # times between places that no longer exist. TravelTime.forget! is why a
  # corrected pin never leaves stale minutes steering the optimizer.
  after_update :forget_travel_times, if: -> { saved_change_to_lat? || saved_change_to_lon? }
  # Gated on zone_changed?: a row written before migration 2600 stays saveable
  # for every other purpose, but no new bad value can be written. Ungated, a
  # single legacy row would roll back an entire AutoFiller transaction.
  validates :zone, inclusion: { in: ZONES }, allow_blank: true, if: :zone_changed?

  # Map a spelling onto the canonical zone. Unknown input comes back UNCHANGED,
  # not nil — silently blanking a typo destroys the only clue anyone has about
  # where that person lives.
  # What to send a geocoder. The street address when we have one, because that
  # is a thing maps know about; the name only as a fallback, which works for
  # "Cary Quadrangle" and not at all for a leasing brand like "Third and West".
  def geocode_query(context = nil)
    [address.presence || name, context || city].compact_blank.join(', ')
  end

  # The city a place actually sits in. Nearly everything we touch is in West
  # Lafayette, but the Lafayette zone is across the Wabash and is a different
  # city with its own street numbering — there is a State Street on both sides.
  # Appending the wrong one sends a driver over a bridge they did not need.
  def city
    zone == 'Lafayette' ? 'Lafayette, Indiana' : 'West Lafayette, Indiana'
  end

  # What to hand Google Maps for this place. A street address beats a lat/lon
  # pair for the driver: it survives being read aloud to a passenger, it is
  # recognisable as somewhere real, and Google resolves it to the building
  # entrance rather than to whichever rooftop point we happened to geocode.
  #
  # nil when there is no address — a whole street, or a complex with no single
  # door — and the caller falls back to coordinates.
  def maps_query
    return nil if address.blank?
    # Some addresses already carry their own city and ZIP, because they had to:
    # a rural grid address needs the ZIP to be unambiguous. Do not append a
    # second city onto one of those.
    return address if address.match?(/lafayette/i)

    "#{address}, #{city}"
  end

  def self.canonical_zone(value)
    return nil if value.blank?

    key = value.to_s.strip
    return key if ZONES.include?(key)

    ZONES.find { |zone| zone.casecmp?(key) } || ZONE_ALIASES[key.downcase] || key
  end

  # Falls back to three letters so an unrecognised zone renders as "ATL" rather
  # than raising inside a Phlex template mid-render. A test asserts ZONES and
  # ZONE_SHORT stay in step, so that fallback should never fire in practice.
  def self.zone_short(zone)
    ZONE_SHORT[zone] || zone.to_s[0, 3].upcase
  end

  def coords
    { lon: lon, lat: lat }
  end

  def coords?
    lat.present? && lon.present?
  end

  def zone_short
    self.class.zone_short(zone)
  end

  def to_s
    "#{name} (#{lon}, #{lat})"
  end

  private

  def forget_travel_times
    TravelTime.forget!(id)
  end

  def canonicalize_zone
    self.zone = self.class.canonical_zone(zone)
  end
end
