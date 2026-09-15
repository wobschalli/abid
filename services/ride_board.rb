require_relative 'auto_filler'

# Everything the ride board needs for one event occurrence, computed once.
#
# Port of the `cols()` / `renderVals()` pair in the Ride Board design: the design
# holds riders, drivers and an `assign` map in component state, whereas here the
# assignment lives in rides.driver_ride_id and the "slot" is an Event.
class RideBoard
  attr_reader :event, :query, :selected_ride_id, :focus_ride_id

  def initialize(event, query: nil, selected_ride_id: nil, focus_ride_id: nil)
    @event = event
    @query = query.to_s.strip.downcase
    @selected_ride_id = selected_ride_id&.to_i
    @focus_ride_id = focus_ride_id&.to_i
  end

  # Every ride for this occurrence, with the associations the board reads, so the
  # view never triggers a query per card.
  def rides
    @rides ||= event.rides
                    .includes(:pickup_location, user: :location)
                    .to_a
  end

  def driver_rides
    @driver_rides ||= rides.select(&:driver?).sort_by { |r| r.display_name.downcase }
  end

  def rider_rides
    @rider_rides ||= rides.select(&:rider?).sort_by { |r| r.display_name.downcase }
  end

  # Drivers actually driving today.
  def cars
    @cars ||= driver_rides.select(&:active?).map { |d| Car.new(d, passengers_for(d), clash_map) }
  end

  def pool
    @pool ||= rider_rides.select { |r| r.active? && r.driver_ride_id.nil? }
  end

  def out_riders
    @out_riders ||= rider_rides.select(&:out?)
  end

  # Pool filtered by the search box, grouped by zone in ZONES order. Zones with
  # nobody in them are dropped, and anyone with no zone set lands in "Unzoned" so
  # they can't silently disappear from the queue.
  def queue_groups
    grouped = visible_pool.group_by { |r| r.zone.presence }
    ordered = Location::ZONES.map { |z| [z, grouped[z]] } + [['Unzoned', grouped[nil]]]
    ordered.filter_map do |zone, riders|
      next if riders.blank?
      { zone: zone, count: riders.size, riders: riders }
    end
  end

  def visible_pool
    return pool if query.empty?
    pool.select do |r|
      r.display_name.downcase.include?(query) || r.zone.to_s.downcase.include?(query)
    end
  end

  def selected
    return nil if selected_ride_id.nil?
    @selected ||= rider_rides.find { |r| r.id == selected_ride_id }
  end

  def focused
    return nil if focus_ride_id.nil?
    @focused ||= rides.find { |r| r.id == focus_ride_id }
  end

  def clash_map
    @clash_map ||= Clash.map_for(rides.map(&:user_id))
  end

  # Memoised: the dispatch bar and every car badge read these, and both cost a
  # query.
  def readiness
    @readiness ||= DispatchReadiness.new(self)
  end

  def dispatch_status
    @dispatch_status ||= DispatchStatus.new(self)
  end

  def clashes_for(ride)
    clash_map[ride.user_id] || []
  end

  # --- counters shown in the header and footer -----------------------------

  def pool_count
    pool.size
  end

  def seated_count
    rider_rides.count { |r| r.active? && r.driver_ride_id.present? }
  end

  def seats_left
    cars.sum(&:seats_free)
  end

  def conflict_count
    cars.sum { |c| c.passengers.count { |p| c.conflict?(p) } }
  end

  def overfull_count
    cars.count(&:over?)
  end

  def warnings
    [].tap do |warn|
      warn << "#{pool_count} still without a ride" if pool_count.positive?
      warn << "#{conflict_count} seated with someone they clash with" if conflict_count.positive?
      warn << "#{overfull_count} #{'car'.pluralize(overfull_count)} over capacity" if overfull_count.positive?
    end
  end

  def warning_text
    warnings.join(' · ')
  end

  # --- sibling occurrences, rendered as the slot tabs ------------------------

  def date
    @date ||= (event.start_time || Time.zone.now).to_date
  end

  def sibling_events
    @sibling_events ||= Event.active
                             .where(start_time: date.all_day)
                             .chronological
                             .to_a
  end

  # One car column: the driver's ride plus who's in it.
  class Car
    attr_reader :ride, :passengers

    def initialize(ride, passengers, clash_map)
      @ride = ride
      @passengers = passengers
      @clash_map = clash_map
    end

    def id = ride.id
    def name = ride.display_name
    def zone = ride.zone
    def seats = ride.capacity
    def used = passengers.size
    def empty? = passengers.empty?
    def over? = used > seats
    def full? = used >= seats
    def seats_free = [seats - used, 0].max
    def seat_text = "#{used} of #{seats} seats"

    def fill_percent
      return 0 if seats.zero?
      [(used.to_f / seats * 100).round, 100].min
    end

    # Two people in this car who have each other on their "won't ride with" list.
    def conflict?(passenger)
      others = passengers.map(&:user_id) - [passenger.user_id]
      (@clash_map[passenger.user_id] || []).intersect?(others)
    end

    # Would seating `rider` here break a clash?
    def clashes_with?(rider)
      (@clash_map[rider.user_id] || []).intersect?(passengers.map(&:user_id))
    end

    # The pill shown on each car while a rider is selected.
    def fit_for(rider)
      return nil if rider.nil?
      return :clash if clashes_with?(rider)
      return :full if full?
      return :closest if zone.present? && zone == rider.zone
      :space
    end
  end

  private

  def passengers_for(driver_ride)
    rider_rides.select { |r| r.driver_ride_id == driver_ride.id && r.active? }
  end
end
