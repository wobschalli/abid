class Ride < ApplicationRecord
  ROLES = %w[rider driver].freeze
  STATUSES = %w[requested assigned confirmed cancelled no_show].freeze

  belongs_to :event
  belongs_to :user
  belongs_to :pickup_location, class_name: 'Location', optional: true

  # A rider points at the driver's ride row for this same event, so a driver's
  # passenger list is scoped to one occurrence instead of being a permanent
  # property of the user (which is what users.driver_id implied).
  belongs_to :driver_ride, class_name: 'Ride', optional: true
  has_many :passengers, class_name: 'Ride', foreign_key: :driver_ride_id, dependent: :nullify

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :event_id }
  validate :driver_ride_must_be_a_driver
  validate :driver_ride_must_be_same_event

  scope :riders, -> { where(role: 'rider') }
  scope :drivers, -> { where(role: 'driver') }
  scope :active, -> { where.not(status: %w[cancelled no_show]) }
  scope :assigned, -> { where.not(driver_ride_id: nil) }
  scope :unassigned, -> { riders.active.where(driver_ride_id: nil) }

  def rider?
    role == 'rider'
  end

  def driver?
    role == 'driver'
  end

  # Falls back to the user's default car capacity; `seats` overrides it for the
  # occasions where someone brings a different car or arrives part-full.
  def capacity
    seats || user&.capacity || 0
  end

  def seats_taken
    passengers.active.count
  end

  def seats_available
    [capacity - seats_taken, 0].max
  end

  def full?
    driver? && seats_available.zero?
  end

  def pickup
    pickup_location || user&.location
  end

  def coords
    pickup&.coords
  end

  def to_s
    "#{user&.name || 'unknown'} (#{role}, #{status})"
  end

  private

  def driver_ride_must_be_a_driver
    return if driver_ride.nil?
    errors.add(:driver_ride, 'must be a driver') unless driver_ride.driver?
  end

  def driver_ride_must_be_same_event
    return if driver_ride.nil?
    errors.add(:driver_ride, 'must be for the same event') unless driver_ride.event_id == event_id
  end
end
