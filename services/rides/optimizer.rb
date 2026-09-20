module Rides
  # Time-optimal seat assignment — what the Auto-fill button and the bot's
  # late-rider sweep both call.
  #
  # A capacitated vehicle-routing problem: each car starts where its driver is
  # (home, or last class on a Friday), collects riders, and everyone ends at the
  # venue. The objective is total driving seconds.
  #
  # Two invariants, and they are the design:
  #
  #   Seated riders never move. Anyone with a car keeps that car — whether a
  #   coordinator placed them by hand or a dispatch already told the driver.
  #   The solver may reorder a car's pickups (DispatchDigest treats riders as a
  #   set, so reordering never re-flags a sent driver), but membership only
  #   ever grows. A late reactor is inserted where they cost least; nobody is
  #   shuffled to make room.
  #
  #   The pool is droppable, the seated are not. Over-capacity leaves people
  #   visibly in the queue rather than failing the solve or evicting someone.
  #
  # Falls back to the greedy zone AutoFiller on ANY failure — gem missing,
  # venue unlocatable, solver infeasible — because this button gets pressed on
  # Sunday mornings and must never 500.
  class Optimizer
    Result = Struct.new(:seated, :dropped, :reordered, :engine, keyword_init: true)

    # Dropping a mandatory-ish visit must always beat a bad route, so the
    # penalty dwarfs any real drive: 8 hours.
    DROP_PENALTY = 8 * 3600
    # Persist an improvement-only re-solve just for beating the old routes by
    # noise? No — two minutes or it did not happen. Keeps the button idempotent
    # even though a time-limited metaheuristic is not deterministic.
    IMPROVEMENT_FLOOR = 120

    def self.call(...)
      new(...).call
    end

    def initialize(board, matrix: nil)
      @board = board
      @event = board.event
      @matrix = matrix || TravelMatrix.new
    end

    # @return [Result] engine: :or_tools or :greedy (the fallback)
    def call
      return Result.new(seated: 0, dropped: 0, reordered: 0, engine: :or_tools) if cars.empty?

      solve
    rescue StandardError, LoadError => e
      warn "optimizer fell back to greedy: #{e.class}: #{e.message}"
      seated = AutoFiller.new(@event).call
      Result.new(seated: seated, dropped: 0, reordered: 0, engine: :greedy)
    end

    private

    def cars
      @cars ||= @board.cars
    end

    def pool
      @pool ||= @board.pool
    end

    def seated
      @seated ||= cars.flat_map { |car| car.passengers.map { |p| [p, car] } }
    end

    def venue_point
      @venue_point ||= begin
        venue = @event.location
        raise 'event has no locatable venue' unless venue&.coords?

        @matrix.point_for(venue)
      end
    end

    def solve
      require "or-tools"

      riders = seated.map(&:first) + pool
      rider_points = riders.map { |ride| @matrix.point_for(ride) }
      driver_points = cars.map { |car| @matrix.point_for(car.ride) || venue_point }

      # A rider the matrix cannot place at all cannot be routed; they stay in
      # the pool rather than being seated somewhere arbitrary.
      routable = riders.each_index.select { |i| rider_points[i] }
      unroutable = riders.size - routable.size

      # Node layout: routable riders, then one start per vehicle, venue last.
      points = routable.map { |i| rider_points[i] } + driver_points + [venue_point]
      @matrix.warm(points)

      rider_count = routable.size
      venue_node = points.size - 1
      starts = Array.new(cars.size) { |v| rider_count + v }
      ends = Array.new(cars.size, venue_node)

      manager = ORTools::RoutingIndexManager.new(points.size, cars.size, starts, ends)
      routing = ORTools::RoutingModel.new(manager)

      # The gem takes callbacks as lambdas, not blocks.
      cost = routing.register_transit_callback(lambda do |from, to|
        @matrix.seconds(points[manager.index_to_node(from)], points[manager.index_to_node(to)])
      end)
      routing.set_arc_cost_evaluator_of_all_vehicles(cost)

      demand = routing.register_unary_transit_callback(
        ->(index) { manager.index_to_node(index) < rider_count ? 1 : 0 }
      )
      routing.add_dimension_with_vehicle_capacity(
        demand, 0, cars.map { |car| [car.seats.to_i, car.passengers.size].max }, true, 'seats'
      )

      pinned = seated.to_h { |ride, car| [ride.id, cars.index(car)] }
      routable.each_with_index do |rider_i, node|
        index = manager.node_to_index(node)
        vehicle = pinned[riders[rider_i].id]
        if vehicle
          # Seated: must be visited, and only by their own car.
          routing.set_allowed_vehicles_for_index([vehicle], index)
        else
          # Pool: seat them if the seats and the clock allow, else leave them
          # where the coordinator can see them.
          routing.add_disjunction([index], DROP_PENALTY)
        end
      end

      search = ORTools.default_routing_search_parameters
      search.first_solution_strategy = :path_cheapest_arc
      search.local_search_metaheuristic = :guided_local_search
      search.time_limit = 2

      solution = routing.solve_with_parameters(search)
      raise 'no feasible assignment' if solution.nil?

      routes = extract_routes(routing, manager, solution, riders, routable, rider_count)
      persist(routes, unroutable)
    end

    def extract_routes(routing, manager, solution, riders, routable, rider_count)
      cars.each_index.map do |vehicle|
        order = []
        index = routing.start(vehicle)
        until routing.end?(index)
          node = manager.index_to_node(index)
          order << riders[routable[node]] if node < rider_count
          index = solution.value(routing.next_var(index))
        end
        [cars[vehicle], order]
      end
    end

    # The guard that makes the button safe to lean on: a solve that seats
    # nobody new only rewrites pickup orders when it found a real improvement,
    # so pressing Auto-fill twice in a row changes nothing.
    def persist(routes, unroutable)
      newly = routes.sum { |car, order| order.count { |ride| ride.driver_ride_id != car.id } }
      improvement = previous_cost - proposed_cost(routes)

      if newly.zero? && improvement < IMPROVEMENT_FLOOR
        return Result.new(seated: 0, dropped: pool.size + unroutable, reordered: 0, engine: :or_tools)
      end

      reordered = 0
      Ride.transaction do
        routes.each do |car, order|
          order.each_with_index do |ride, position|
            if ride.driver_ride_id != car.id
              ride.update!(driver_ride_id: car.id, status: 'assigned', pickup_position: position)
            elsif ride.pickup_position != position
              ride.update!(pickup_position: position)
              reordered += 1
            end
          end
        end
      end

      Result.new(seated: newly, dropped: pool.size - newly + unroutable,
                 reordered: reordered, engine: :or_tools)
    end

    # Cost of the routes as they stand, in the stored (or default) order — the
    # bar a re-solve has to clear before its shuffle is worth anybody's time.
    def previous_cost
      cars.sum do |car|
        stops = car.passengers.sort_by { |p| [p.pickup_position || 1 << 30, p.display_name.to_s] }
        route_cost(car, stops)
      end
    end

    def proposed_cost(routes)
      routes.sum { |car, order| route_cost(car, order) }
    end

    def route_cost(car, stops)
      here = @matrix.point_for(car.ride) || venue_point
      total = 0
      stops.each do |ride|
        there = @matrix.point_for(ride) or next
        total += @matrix.seconds(here, there)
        here = there
      end
      total + @matrix.seconds(here, venue_point)
    end
  end
end
