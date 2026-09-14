# Greedy seat assignment — the "Auto-fill" button.
#
# Deliberately simple and fully overridable: it only ever fills empty seats, it
# never moves someone who is already seated, and a coordinator can drag anyone
# anywhere afterwards. Rides have constraints no solver knows about.
class AutoFiller
  STRATEGIES = {
    'closest' => 'Closest zone first',
    'spread' => 'Spread evenly'
  }.freeze

  def initialize(event, strategy: 'closest')
    @event = event
    @strategy = STRATEGIES.key?(strategy.to_s) ? strategy.to_s : 'closest'
  end

  # @return [Integer] how many riders were seated
  def call
    return 0 if drivers.empty?

    seated = 0
    Ride.transaction do
      unassigned.each do |rider|
        car = best_car_for(rider)
        next if car.nil?

        rider.update!(driver_ride_id: car.id, status: 'assigned')
        load[car.id] += 1
        seated_user_ids[car.id] << rider.user_id
        seated += 1
      end
    end
    seated
  end

  private

  attr_reader :event, :strategy

  def spread?
    strategy == 'spread'
  end

  def rides
    @rides ||= event.rides.includes(:user, :pickup_location).to_a
  end

  def drivers
    @drivers ||= rides.select { |r| r.driver? && r.active? }
  end

  def unassigned
    @unassigned ||= rides.select { |r| r.rider? && r.active? && r.driver_ride_id.nil? }
                         .sort_by { |r| r.display_name.downcase }
  end

  def clash_map
    @clash_map ||= Clash.map_for(rides.map(&:user_id))
  end

  # Mutated as we go, so a car filled during this run is seen as full by the
  # riders considered after it.
  def load
    @load ||= drivers.to_h { |d| [d.id, rides.count { |r| r.rider? && r.active? && r.driver_ride_id == d.id }] }
  end

  def seated_user_ids
    @seated_user_ids ||= drivers.to_h do |d|
      [d.id, rides.select { |r| r.rider? && r.active? && r.driver_ride_id == d.id }.map(&:user_id)]
    end
  end

  def best_car_for(rider)
    avoid = clash_map[rider.user_id] || []

    candidates = drivers.reject { |d| load[d.id] >= d.capacity }
                        .reject { |d| seated_user_ids[d.id].intersect?(avoid) }

    return nil if candidates.empty?

    candidates.min_by { |d| sort_key(d, rider) }
  end

  # Lower sorts first. `free` is the fraction of the car still empty, negated so
  # the emptiest car wins ties.
  def sort_key(driver, rider)
    free = driver.capacity.positive? ? (driver.capacity - load[driver.id]).to_f / driver.capacity : 0.0
    return [-free, driver.id] if spread?

    same_zone = driver.zone.present? && driver.zone == rider.zone ? 0 : 1
    [same_zone, -free, driver.id]
  end
end
