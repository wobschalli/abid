class User < ApplicationRecord
  # Home / default pickup point. Optional because members are auto-created from
  # Discord joins long before anyone tells us where they live.
  belongs_to :location, optional: true

  has_many :rides, dependent: :destroy
  has_and_belongs_to_many :events
  has_and_belongs_to_many :roles

  has_secure_password

  scope :leaders, -> { where(leader: true) }
  scope :drivers, -> { where.not(capacity: nil).where('capacity > 0') }
  scope :by_name, -> { order(Arel.sql('lower(coalesce(name, username))')) }

  def display_name
    name.presence || username.presence || "user #{discord_id}"
  end

  def can_drive?
    capacity.to_i.positive?
  end

  # The ride this user has for a given event, if any.
  def ride_for(event)
    rides.find_by(event_id: event.id)
  end

  def to_s
    display_name
  end
end
