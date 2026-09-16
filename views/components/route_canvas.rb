require_relative 'components'

# The drawn routes.
#
# Its own Phlex::SVG component because SVG child elements — polyline, circle,
# rect, text — are not registered on Phlex::HTML. Trying to emit them from an
# HTML view silently resolves `text` and `s` to unrelated HTML methods.
class Components::RouteCanvas < Phlex::SVG
  def initialize(map:, event:, colour:)
    @map = map
    @event = event
    @colour = colour
  end

  def view_template
    svg(viewBox: "0 0 #{RouteMap::WIDTH} #{RouteMap::HEIGHT}",
        width: '100%', role: 'img',
        aria_label: "Pickup routes for #{@event.name}",
        class: 'block w-full h-auto',
        xmlns: 'http://www.w3.org/2000/svg') do
      # Lines first so the stop markers sit on top of them.
      @map.routes.each { |route| route_line(route) }
      @map.routes.each { |route| route_stops(route) }
      destination_marker
    end
  end

  private

  def route_line(route)
    return if route.points.size < 2

    polyline(
      points: route.points.map { |p| "#{p.x.round(1)},#{p.y.round(1)}" }.join(' '),
      fill: 'none',
      stroke: @colour.call(route.slot),
      stroke_width: '2',
      stroke_linejoin: 'round',
      stroke_linecap: 'round',
      opacity: '0.85'
    )
  end

  # A surface-coloured ring keeps overlapping pins legible where two people are
  # collected from the same block.
  def route_stops(route)
    route.pickups.each_with_index do |point, i|
      circle(cx: point.x.round(1), cy: point.y.round(1), r: '9',
             fill: @colour.call(route.slot),
             stroke: 'var(--color-surface)', stroke_width: '2')
      text(x: point.x.round(1), y: (point.y + 3.5).round(1),
           text_anchor: 'middle', font_size: '10', font_weight: '700',
           fill: '#ffffff') { (i + 1).to_s }
    end
  end

  def destination_marker
    point = @map.destination
    return if point.nil?

    rect(x: (point.x - 8).round(1), y: (point.y - 8).round(1),
         width: '16', height: '16', rx: '4',
         fill: 'var(--color-ink)', stroke: 'var(--color-surface)', stroke_width: '2')
    text(x: point.x.round(1), y: (point.y - 14).round(1),
         text_anchor: 'middle', font_size: '11', font_weight: '600',
         fill: 'var(--color-ink)') { point.stop.name.to_s }
  end
end
