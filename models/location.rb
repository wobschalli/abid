class Location < ApplicationRecord
  has_many :events
  has_many :users

  scope :search_by_name, ->(name) {where(name: name).or(where("'#{name}' = ANY (aliases)"))}
  scope :search_by_coords, ->(lat, lon) { where(lon: lon).where(lat: lat) }

  def coords
    { lon: lon, lat: lat }
  end

  def to_s
    "#{name} (#{lon}, #{lat})"
  end
end
