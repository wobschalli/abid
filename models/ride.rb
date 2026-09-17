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
  # Deliberately NOT `dependent: :nullify`. That option registers its own
  # before_destroy when the association is declared, so it ran first and cleared
  # driver_ride_id before anything else could look at the passengers — leaving
  # `unseat_passengers` with an empty set and riders still marked 'assigned'.
  # Doing both here, in order, is the only way they stay consistent.
  has_many :passengers, class_name: 'Ride', foreign_key: :driver_ride_id

  has_many :signup_reactions, dependent: :nullify

  before_validation :canonicalize_zone
  # Deleting a driver puts their riders back in the waiting queue, rather than
  # taking them off the board along with the car. Somebody who dropped out of
  # driving has not told us anything about whether their passengers still need
  # a lift — they do, and they are now the most urgent people on the board.
  before_destroy :unseat_passengers

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

  # What to put in the driver's Google Maps link for this pickup.
  #
  # Typed text first — it is a correction to where the pin sits ("north door",
  # "apt 412"), and it is the more specific of the two. Then the location's own
  # street address. nil when we have neither, and the route falls back to the
  # coordinates.
  #
  # The typed text is passed through with the city appended only when it does
  # not already name one, so "123 Vine St, Lafayette" is not turned into
  # "123 Vine St, Lafayette, West Lafayette, Indiana".
  def pickup_maps_query
    return pickup&.maps_query if pickup_address.blank?

    typed = pickup_address.strip
    return typed if typed.match?(/lafayette/i)

    [typed, pickup&.city || 'West Lafayette, Indiana'].join(', ')
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

  def to_s
    "#{user&.name || 'unknown'} (#{role}, #{status})"
  end

  private

  # Status first, while the riders are still linked to this car; then the link.
  #
  # Only 'assigned' is reset: that status means "seated in a car", and the car
  # is going. A rider who had confirmed or cancelled said something about
  # themselves, not about this driver, and that survives.
  def unseat_passengers
    passengers.where(status: 'assigned').update_all(status: 'requested', updated_at: Time.current)
    passengers.update_all(driver_ride_id: nil, updated_at: Time.current)
  end

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
