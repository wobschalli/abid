class Matcher
  def initialize(bot)
    @bot = bot
    @map = Map.new
  end

  def match_riders_to_drivers(event, riders, drivers)
    rider_drivers_list = knn_by_proximity(riders, drivers)
    assignments, unassigned_riders = knapsack_assignment(rider_drivers_list)
    optimized_routes = optimize_routes(assignments)
    save_assignments(event, optimized_routes)
    notify_drivers(event, optimized_routes)

    [optimized_routes, unassigned_riders]
  end

  private

  def knn_by_proximity(riders, drivers, k=3)
    riders.map do |rider|
      closest_drivers = drivers
                          .sort_by!{ |driver| distance(rider.location, driver.location) }
                          .first(k)
      { rider: rider, driver_candidates: closest_drivers }
    end
  end

  def knapsack_assignment(rider_drivers_list)
    assignments = []
    unassigned_riders = []
    drivers_with_capacity = rider_drivers_list
                              .flat_map { |pair| pair[:driver_candidates] }
                              .uniq
                              .map { |driver| { driver: driver, capacity: driver.capacity, riders: [] } }

    rider_drivers_list.each do |pair|
      pair => { rider:, driver_candidates: }
      assigned = false

      driver_candidates.each do |driver|
        driver_slot = drivers_with_capacity.find { |d| d[:driver] == driver }

        if driver_slot && driver_slot[:capacity] > driver_slot[:riders].length
          driver_slot[:riders] << rider
          assigned = true
          break
        end
      end

      unassigned_riders << rider unless assigned
    end

    drivers_with_capacity.select { |d| d[:riders].any? }.map do |assignment|
      assignments << { driver: assignment[:driver], riders: assignment[:riders] }
    end

    [assignments, unassigned_riders]
  end

  def optimize_routes(assignments)
    assignments.map do |assignment|
      assignment => { driver:, riders: }

      rider_locations = riders.map { |r| [r.location.lon, r.location.lat] }

      optimized_route = @map.create_trip(rider_locations)
      { driver: driver, riders: riders, route: optimized_route}
    end
  end

  def distance(loc1, loc2)
    Math.sqrt(
      ((loc1.lat - loc2.lat) * 111.32) ** 2 +
      ((loc1.lon - loc2.lon) * Math.cos(
        (loc1.lat + loc2.lat) / 2 * Math::PI / 180
      ) * 111.32) ** 2
    )
  end

  def save_assignments(event, assignments)
    assignments.each do |assignment|
      assignment[:riders].each do |rider|
        RideAssignment.create(
          event: event,
          driver: assignment[:driver],
          user: rider,
          route: assignment[:route]
        )
      end
    end
  end

  def notify_drivers(event, assignments)
    assignments.each do |assignment|
      assignment[:riders].each do |rider|
        rider_msg = "You have been assigned to driver #{assignment[:driver].name} " +
                    "for the event #{event.name}."
        @bot.client.user(rider.discord_id).dm(rider_msg)
      end
      riders_list = assignment[:riders].map(&:name).join(", ")
      driver_msg = "Pickup route for #{event.name}:" +
                   "\n #{assignment[:route].join(" → ")}\nRiders: #{riders_list}"
      @bot.client.user(assignment[:driver].discord_id).dm(driver_msg)
    end
  end
end
