class Ride < ApplicationRecord
  ROLES = %w[rider driver].freeze
  STATUSES = %w[requested assigned confirmed cancelled no_show].freeze

  # Who created this row. Reaction handling only ever touches 'discord' rides,
  # so a rider a coordinator added by hand cannot be removed by Discord traffic.
  SOURCES = %w[manual discord].freeze

  # Statuses that take someone off the board for the day. The design calls this
  # "not coming" for riders and "not driving today" for drivers.
  OUT_STATUSES = %w[cancelled no_show].freeze

  belongs_to :event
  belongs_to :user
  belongs_to :pickup_location, class_name: 'Location', optional: true

  # A rider points at the driver's ride row for this same event, so a driver's
  # passenger list is scoped to one occurrence instead of being a permanent
  # property of the user (which is what users.driver_id implied).
  belongs_to :driver_ride, class_name: 'Ride', optional: true
  has_many :passengers, class_name: 'Ride', foreign_key: :driver_ride_id, dependent: :nullify

  has_many :signup_reactions, dependent: :nullify

  before_validation :canonicalize_zone

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  # Same gate as Location: rides.zone wins over the location's zone, so a bad
  # value here overrides good data — but an unconditional validation would let
  # one legacy row roll back a whole AutoFiller transaction.
  validates :zone, inclusion: { in: Location::ZONES }, allow_blank: true, if: :zone_changed?
  validates :user_id, uniqueness: { scope: :event_id }
  validate :driver_ride_must_be_a_driver
  validate :driver_ride_must_be_same_event

  scope :riders, -> { where(role: 'rider') }
  scope :drivers, -> { where(role: 'driver') }
  scope :active, -> { where.not(status: OUT_STATUSES) }
  scope :out, -> { where(status: OUT_STATUSES) }
  scope :assigned, -> { where.not(driver_ride_id: nil) }
  scope :unassigned, -> { riders.active.where(driver_ride_id: nil) }
  scope :in_zone, ->(zone) { where(zone: zone) }
  scope :from_discord, -> { where(source: 'discord') }
  scope :dropped, -> { where.not(dropped_at: nil) }

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

  # A per-occurrence override always wins; otherwise the event decides which of
  # the person's two addresses to use, falling back to home when they never
  # told us where their Friday class is.
  def pickup
    pickup_location || user_pickup
  end

  def user_pickup
    return nil if user.nil?
    return user.location if event&.pickup_source != 'class'

    user.class_location || user.location
  end

  def coords
    pickup&.coords
  end

  # Per-occurrence override wins, then the pickup location's zone.
  def zone
    self[:zone].presence || pickup&.zone
  end

  def zone_short
    Location.zone_short(zone)
  end

  # What the details rail shows in the address field: the free text the
  # coordinator typed, falling back to whatever location we have on file.
  def address
    pickup_address.presence || pickup&.name
  end

  def out?
    OUT_STATUSES.include?(status)
  end

  def from_discord?
    source == 'discord'
  end

  # Un-reacted after a coordinator had already seated them. The seat is freed
  # but the row stays on the board rather than silently vanishing.
  def dropped?
    dropped_at.present?
  end

  def active?
    !out?
  end

  def display_name
    user&.display_name.to_s
  end

  # Riders this one must not share a car with.
  def clash_user_ids
    @clash_user_ids ||= Clash.ids_for(user_id)
  end

  def to_s
    "#{user&.name || 'unknown'} (#{role}, #{status})"
  end

  private

  # `self[:zone]`, never `self.zone` — the reader below is overridden to fall
  # through to the pickup location, so `self.zone = zone` would copy the
  # location's zone onto the ride and destroy the "no override" state.
  def canonicalize_zone
    self[:zone] = Location.canonical_zone(self[:zone])
  end

  def driver_ride_must_be_a_driver
    return if driver_ride.nil?
    errors.add(:driver_ride, 'must be a driver') unless driver_ride.driver?
  end

  def driver_ride_must_be_same_event
    return if driver_ride.nil?
    errors.add(:driver_ride, 'must be for the same event') unless driver_ride.event_id == event_id
  end
end
