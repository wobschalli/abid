require_relative '../map/map'

# Writes from the details rail and the "add someone" form.
#
# Fields are split across two tables on purpose: a phone number and a name are
# facts about the person and should persist between weeks, whereas the pickup
# spot, seat count and notes are per-occurrence.
class RideDetails
  USER_FIELDS = %w[name phone].freeze
  RIDE_FIELDS = %w[zone pickup_address note seats].freeze

  def initialize(ride)
    @ride = ride
  end

  def apply(params)
    Ride.transaction do
      update_user(params)
      update_ride(params)
      geocode_pickup
    end
    @ride
  end

  def self.create_for(event, params)
    user = User.find(params[:user_id])
    role = Ride::ROLES.include?(params[:role].to_s) ? params[:role].to_s : 'rider'

    event.rides.create!(
      user: user,
      role: role,
      status: 'requested',
      zone: params[:zone].presence || user.location&.zone,
      seats: role == 'driver' ? (user.capacity.presence || 4) : nil,
      signed_up_at: Time.zone.now
    )
  end

  private

  def update_user(params)
    user = @ride.user
    return if user.nil?

    attrs = {}
    # A blank name would wipe the Discord-synced display name, so ignore it.
    attrs[:name] = params['name'] if params['name'].present?
    # A blank phone, on the other hand, is a deliberate clear.
    attrs[:phone] = params['phone'].presence if params.key?('phone')

    user.update!(attrs) if attrs.any?
  end

  def update_ride(params)
    attrs = params.slice(*RIDE_FIELDS)
    attrs['seats'] = normalize_seats(attrs['seats']) if attrs.key?('seats')
    attrs['zone'] = attrs['zone'].presence if attrs.key?('zone')
    @ride.update!(attrs)
  end

  def normalize_seats(value)
    return nil if value.blank?
    [[value.to_i, 1].max, 20].min
  end

  # Best-effort: turn the typed address into a real Location so the route
  # suggestion in map.rb has coordinates to work with. Never blocks the save —
  # OSM is a third party and the board has to stay usable on a Sunday morning.
  def geocode_pickup
    address = @ride.pickup_address
    return if address.blank?
    return if @ride.pickup_location&.name == address

    existing = Location.search_by_name(address).first
    location = existing || safely { Map.new.create_new_location(address) }
    return if location.nil?

    location.update(zone: @ride.zone) if location.zone.blank? && @ride.zone.present?
    @ride.update_column(:pickup_location_id, location.id)
  end

  def safely
    yield
  rescue StandardError => e
    warn "geocoding failed for ride #{@ride.id}: #{e.class}: #{e.message}"
    nil
  end
end
