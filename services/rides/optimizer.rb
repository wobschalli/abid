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
  #   Nobody a human or a dispatch has committed to ever moves. Two kinds of
  #   seating are sacred: any rider in a car whose driver has been told
  #   (queued/sent/confirmed), and any rider a coordinator placed by hand.
  #   The optimizer's OWN pre-dispatch placements are neither — it may revise
  #   itself freely until a driver has been messaged, which is what lets a
  #   re-press fix a layout the constraints have since outlawed. The tell is
  #   pickup_position: the optimizer always writes one, hand-seating never
  #   does, and a manual re-drag clears it.
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
    # Pulling over, loading, seatbelts, going again. Without this a stop is
    # free and the cheapest plan is one car snaking through every pickup —
    # total driving time genuinely IS lowest that way, and it is still the
    # wrong answer, because minutes-per-stop is what the sheet coordinator
    # was implicitly pricing in.
    STOP_SECONDS = 90
    # No car's route may exceed this, driving plus stops. This is the arrival
    # deadline wearing constraint clothes: pickups start ~20 minutes before
    # the service, so a 26-stop snake is not late-ish, it is impossible.
    MAX_ROUTE_SECONDS = 30 * 60
    # Mild pressure to even routes out once the hard cap is satisfied. Small
    # on purpose: 3 means a minute of imbalance costs three minutes of
    # objective, enough to spread riders without chasing perfect symmetry.
    SPAN_COST = 3
    # How far somebody can reasonably be asked to walk to a meeting-point
    # vehicle: ~15 minutes at a student walking pace, as the crow flies.
    WALK_METERS = 1200
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

      walked = fill_meeting_points
      result = solve
      Result.new(seated: result.seated + walked, dropped: result.dropped,
                 reordered: result.reordered, engine: result.engine)
    rescue StandardError, LoadError => e
      warn "optimizer fell back to greedy: #{e.class}: #{e.message}"
      seated = AutoFiller.new(@event).call
      Result.new(seated: seated, dropped: 0, reordered: 0, engine: :greedy)
    end

    private

    # Meeting-point vehicles fill FIRST, before any driving is planned. Their
    # riders walk over, so a seat there costs zero driving — the cheapest seat
    # on the board by definition, which is exactly why the coordinator wants
    # the van packed before the cars start routing.
    #
    # Nearest-first within walking range, so when the van cannot take everyone
    # the people left to the cars are the ones a car was going to pass anyway.
    # Skips frozen vehicles: a van whose driver has been dispatched keeps its
    # roster like any other sent car.
    def fill_meeting_points
      walked = 0
      meeting_cars.each do |car|
        next if %i[queued sent confirmed].include?(@board.dispatch_status.state_for(car.ride))

        spot = @matrix.point_for(car.ride)
        next if spot.nil?

        free = car.seats.to_i - car.passengers.size
        next if free <= 0

        candidates = pool.filter_map do |ride|
          point = @matrix.point_for(ride)
          next if point.nil?

          meters = straight_line_meters(spot, point)
          [ride, meters] if meters <= WALK_METERS
        end

        candidates.sort_by { |_, meters| meters }.first(free).each_with_index do |(ride, _), i|
          ride.update!(driver_ride_id: car.id, status: 'assigned',
                       pickup_position: car.passengers.size + i)
          walked += 1
        end
      end
      reset_board_state if walked.positive?
      walked
    end

    def meeting_cars
      cars.select { |car| car.ride.meet_at_pickup }
    end

    def straight_line_meters(a, b)
      dy = (a.lat - b.lat) * 111_000
      dx = (a.lon - b.lon) * 111_000 * Math.cos(a.lat * Math::PI / 180)
      Math.sqrt((dx * dx) + (dy * dy))
    end

    # The pre-pass changed who is seated, so every memoised view of the board
    # is stale.
    def reset_board_state
      @cars = @pool = @seated = nil
      @board = RideBoard.new(@event)
    end

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

      # Meeting-point vehicles do not drive routes — whoever walked to them is
      # settled, and their remaining seats are not fillable by driving.
      driving = cars.reject { |car| car.ride.meet_at_pickup }
      return Result.new(seated: 0, dropped: pool.size, reordered: 0, engine: :or_tools) if driving.empty?

      riders = seated.reject { |_, car| car.ride.meet_at_pickup }.map(&:first) + pool
      rider_points = riders.map { |ride| @matrix.point_for(ride) }
      driver_points = driving.map { |car| @matrix.point_for(car.ride) || venue_point }

      # A rider the matrix cannot place at all cannot be routed; they stay in
      # the pool rather than being seated somewhere arbitrary.
      routable = riders.each_index.select { |i| rider_points[i] }
      unroutable = riders.size - routable.size

      # Node layout: routable riders, then one start per vehicle, venue last.
      points = routable.map { |i| rider_points[i] } + driver_points + [venue_point]
      @matrix.warm(points)

      rider_count = routable.size
      venue_node = points.size - 1
      starts = Array.new(driving.size) { |v| rider_count + v }
      ends = Array.new(driving.size, venue_node)

      manager = ORTools::RoutingIndexManager.new(points.size, driving.size, starts, ends)
      routing = ORTools::RoutingModel.new(manager)

      # The gem takes callbacks as lambdas, not blocks.
      cost = routing.register_transit_callback(lambda do |from, to|
        node = manager.index_to_node(from)
        travel = @matrix.seconds(points[node], points[manager.index_to_node(to)])
        # Service time rides on the outgoing arc of each pickup.
        node < rider_count ? travel + STOP_SECONDS : travel
      end)
      routing.set_arc_cost_evaluator_of_all_vehicles(cost)

      # The clock, as a hard per-route cap plus gentle balancing. The cap is
      # what actually breaks up the snake: the objective alone will always
      # prefer one long sweep, because every car's own drive to the venue is
      # paid whether or not it carries anyone.
      routing.add_dimension(cost, 0, MAX_ROUTE_SECONDS, true, 'time')
      routing.mutable_dimension('time').set_global_span_cost_coefficient(SPAN_COST)

      demand = routing.register_unary_transit_callback(
        ->(index) { manager.index_to_node(index) < rider_count ? 1 : 0 }
      )
      routing.add_dimension_with_vehicle_capacity(
        demand, 0, driving.map { |car| [car.seats.to_i, car.passengers.size].max }, true, 'seats'
      )

      frozen_cars = driving.each_index.select do |v|
        %i[queued sent confirmed].include?(@board.dispatch_status.state_for(driving[v].ride))
      end.to_set

      pinned = {}
      movable_but_seated = []
      seated.reject { |_, car| car.ride.meet_at_pickup }.each do |ride, car|
        vehicle = driving.index(car)
        if frozen_cars.include?(vehicle) || ride.pickup_position.nil?
          pinned[ride.id] = vehicle
        else
          # The optimizer's own pre-dispatch placement: must stay seated
          # somewhere, but not owed this particular car.
          movable_but_seated << ride.id
        end
      end

      routable.each_with_index do |rider_i, node|
        index = manager.node_to_index(node)
        ride = riders[rider_i]
        if (vehicle = pinned[ride.id])
          routing.set_allowed_vehicles_for_index([vehicle], index)
        elsif !movable_but_seated.include?(ride.id)
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

      routes = extract_routes(routing, manager, solution, riders, routable, rider_count, driving)
      persist(routes, unroutable)
    end

    def extract_routes(routing, manager, solution, riders, routable, rider_count, driving)
      driving.each_index.map do |vehicle|
        order = []
        index = routing.start(vehicle)
        until routing.end?(index)
          node = manager.index_to_node(index)
          order << riders[routable[node]] if node < rider_count
          index = solution.value(routing.next_var(index))
        end
        [driving[vehicle], order]
      end
    end

    # The guard that makes the button safe to lean on: a solve that seats
    # nobody new only rewrites pickup orders when it found a real improvement,
    # so pressing Auto-fill twice in a row changes nothing.
    def persist(routes, unroutable)
      newly = routes.sum { |car, order| order.count { |ride| ride.driver_ride_id != car.id } }
      improvement = previous_cost - proposed_cost(routes)

      if newly.zero? && improvement < IMPROVEMENT_FLOOR && !current_routes_overlong?
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

    # The idempotence guard must not preserve a layout the constraints now
    # forbid: after the route-length cap was added, boards optimized under the
    # old objective sat in 26-stop snakes that a re-press "improved" by zero
    # total seconds — and so refused to fix.
    def current_routes_overlong?
      cars.reject { |c| c.ride.meet_at_pickup }.any? do |car|
        stops = car.passengers.sort_by { |p| [p.pickup_position || 1 << 30, p.display_name.to_s] }
        route_cost(car, stops) > MAX_ROUTE_SECONDS
      end
    end

    # Cost of the routes as they stand, in the stored (or default) order — the
    # bar a re-solve has to clear before its shuffle is worth anybody's time.
    def previous_cost
      cars.reject { |c| c.ride.meet_at_pickup }.sum do |car|
        stops = car.passengers.sort_by { |p| [p.pickup_position || 1 << 30, p.display_name.to_s] }
        route_cost(car, stops)
      end
    end

    def proposed_cost(routes)
      routes.sum { |car, order| route_cost(car, order) }
    end

    # Same metric the solver prices: travel plus a stop's worth of loading per
    # pickup. Measuring the old routes in old units would make every rebalance
    # look like a regression.
    def route_cost(car, stops)
      here = @matrix.point_for(car.ride) || venue_point
      total = 0
      stops.each do |ride|
        there = @matrix.point_for(ride) or next
        total += @matrix.seconds(here, there) + STOP_SECONDS
        here = there
      end
      total + @matrix.seconds(here, venue_point)
    end
  end
end
