class Location < ApplicationRecord
  # Coarse pickup areas the ride board groups and auto-fills by. Edit this list
  # to match your actual geography; SHORT is what the roster rail shows.
  ZONES = %w[North Campus Downtown East].freeze
  ZONE_SHORT = { 'North' => 'N', 'Campus' => 'CMP', 'Downtown' => 'DT', 'East' => 'E' }.freeze

  has_many :events
  has_many :users
  has_many :rides, foreign_key: :pickup_location_id

  # `where("'#{name}' = ANY (aliases)")` interpolated straight into SQL, and the
  # value comes from a Discord modal — a location named `x') OR ('1'='1` was a
  # working injection. Bound parameter now.
  scope :search_by_name, lambda { |name|
    where(name: name).or(where('? = ANY (aliases)', name.to_s))
  }
  scope :search_by_coords, ->(lat, lon) { where(lon: lon).where(lat: lat) }
  scope :in_zone, ->(zone) { where(zone: zone) }

  validates :zone, inclusion: { in: ZONES }, allow_blank: true

  def self.zone_short(zone)
    ZONE_SHORT[zone] || zone.to_s[0, 3].upcase
  end

  def coords
    { lon: lon, lat: lat }
  end

  def to_s
    "#{name} (#{lon}, #{lat})"
  end
end
