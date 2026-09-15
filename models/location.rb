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
  scope :search_by_name, lambda { |name|
    key = name.to_s.strip.downcase
    where('lower(name) = ?', key)
      .or(where('EXISTS (SELECT 1 FROM unnest(aliases) a WHERE lower(a) = ?)', key))
  }
  scope :search_by_coords, ->(lat, lon) { where(lon: lon).where(lat: lat) }
  scope :in_zone, ->(zone) { where(zone: zone) }
  scope :zoned, -> { where.not(zone: nil) }

  before_validation :canonicalize_zone
  # Gated on zone_changed?: a row written before migration 2600 stays saveable
  # for every other purpose, but no new bad value can be written. Ungated, a
  # single legacy row would roll back an entire AutoFiller transaction.
  validates :zone, inclusion: { in: ZONES }, allow_blank: true, if: :zone_changed?

  # Map a spelling onto the canonical zone. Unknown input comes back UNCHANGED,
  # not nil — silently blanking a typo destroys the only clue anyone has about
  # where that person lives.
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

  def canonicalize_zone
    self.zone = self.class.canonical_zone(zone)
  end
end
