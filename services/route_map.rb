# Projects each driver's route onto a flat canvas so the board can draw it.
#
# Server-rendered SVG rather than a tile map on purpose. The app has no
# client-side map library, tiles are a third party on every page load, and the
# question this answers does not need streets: "is this route sane, or is a
# driver crossing town twice?" is about relative geometry, which dots and lines
# carry perfectly well. Drivers navigate from the Google Maps link in their DM,
# which already has real turn-by-turn.
class RouteMap
  Point = Struct.new(:x, :y, :stop, :index, keyword_init: true)
  Route = Struct.new(:car, :plan, :points, :slot, keyword_init: true) do
    def name = car.name
    # The destination is shared by every route, so it is drawn once rather than
    # once per driver.
    def pickups = points.reject { |p| p.stop.kind == :destination }
  end

  WIDTH = 760
  HEIGHT = 520
  PAD = 46

  def initialize(board, width: WIDTH, height: HEIGHT)
    @board = board
    @width = width
    @height = height
  end

  def routes
    @routes ||= plans.each_with_index.map do |(car, plan), i|
      Route.new(car: car, plan: plan, slot: i, points: plan.stops.each_with_index.filter_map do |stop, n|
        project(stop, n) if stop.coords?
      end)
    end
  end

  # Where everyone is heading — one marker, not one per car.
  def destination
    @destination ||= begin
      stop = plans.map { |_, plan| plan.destination }.compact.find(&:coords?)
      stop && project(stop, nil)
    end
  end

  # Named on the page rather than dropped, so a missing pin is a thing you can
  # go and fix instead of a silent gap in the picture.
  def unplotted
    @unplotted ||= plans.flat_map { |_, plan| plan.stops.reject(&:coords?) }.uniq(&:label)
  end

  def any?
    routes.any? { |r| r.points.size > 1 } || destination
  end

  private

  def plans
    @plans ||= @board.cars.map { |car| [car, RoutePlanner.new(car, event: @board.event).call] }
  end

  def coordinates
    @coordinates ||= plans.flat_map { |_, plan| plan.stops.select(&:coords?) }
                          .map { |s| [s.lat.to_f, s.lon.to_f] }
  end

  # Equirectangular, which is fine over a few kilometres, with longitude
  # squeezed by cos(latitude) so the town is not stretched sideways.
  def bounds
    @bounds ||= begin
      lats = coordinates.map(&:first)
      lons = coordinates.map(&:last)
      # A single stop has no extent; give it one so the scale is not a division
      # by zero and the pin lands in the middle.
      pad_lat = [(lats.max - lats.min) * 0.15, 0.002].max
      pad_lon = [(lons.max - lons.min) * 0.15, 0.002].max
      { lat: (lats.min - pad_lat)..(lats.max + pad_lat),
        lon: (lons.min - pad_lon)..(lons.max + pad_lon) }
    end
  end

  def scale
    @scale ||= begin
      mid = (bounds[:lat].first + bounds[:lat].last) / 2
      squeeze = Math.cos(mid * Math::PI / 180)
      span_x = (bounds[:lon].last - bounds[:lon].first) * squeeze
      span_y = bounds[:lat].last - bounds[:lat].first
      # One scale for both axes, so the shape is not distorted.
      [(@width - (PAD * 2)) / span_x, (@height - (PAD * 2)) / span_y].min
    end
  end

  def project(stop, index)
    mid = (bounds[:lat].first + bounds[:lat].last) / 2
    squeeze = Math.cos(mid * Math::PI / 180)

    x = ((stop.lon.to_f - bounds[:lon].first) * squeeze * scale) + PAD
    # SVG y grows downward; north should be up.
    y = @height - PAD - ((stop.lat.to_f - bounds[:lat].first) * scale)

    Point.new(x: centre_x + x - drawn_width / 2.0, y: y, stop: stop, index: index)
  end

  # Centres the drawing when one axis uses less than the full canvas.
  def centre_x = @width / 2.0

  def drawn_width
    @drawn_width ||= begin
      mid = (bounds[:lat].first + bounds[:lat].last) / 2
      squeeze = Math.cos(mid * Math::PI / 180)
      ((bounds[:lon].last - bounds[:lon].first) * squeeze * scale) + (PAD * 2)
    end
  end
end
