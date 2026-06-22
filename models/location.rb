class Location < ApplicationRecord
  has_many :events
  has_many :users

  scope :search_by_name, ->(name) {
    term = name.to_s.strip
    where("LOWER(name) = LOWER(?)", term).or(where("? = ANY (aliases)", term))
  }
  scope :search_by_coords, ->(lat, lon) { where(lon: lon).where(lat: lat) }

  validates :name, presence: true

  def coords
    { lon: lon, lat: lat }
  end

  def to_s
    "#{name} (#{lon}, #{lat})"
  end
end
