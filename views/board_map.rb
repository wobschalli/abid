require_relative 'components/master'

# The routes for one occurrence, drawn on a real basemap.
#
# It answers one question the car columns cannot: does this look sane, or is a
# driver crossing town twice to collect someone who is plainly on another
# driver's way? Auto-fill sorts by zone, which is a coarse proxy for geography,
# so this is where you catch it doing something daft.
#
# This began as a server-rendered SVG — dots and lines on blank white. The
# geometry was right and it was still useless: with no streets underneath there
# is nothing to recognise, so you cannot judge whether a line is sensible. The
# basemap is the point, not decoration.
class BoardMap < Phlex::HTML
  include Components

  def initialize(board:, map:, tiles:, leader: false)
    @board = board
    @map = map
    @tiles = tiles
    @leader = leader
  end

  def view_template
    Layout(title: "Map — #{@board.event.name}", leader: @leader) do
      div(class: 'max-w-5xl flex flex-col gap-4 font-sans text-ink') do
        header
        @map.any? ? figure : empty_note
        unplotted_note if @map.unplotted.any?
      end
    end
  end

  private

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      div(class: 'flex flex-col gap-0.5') do
        h1(class: 'font-display font-bold text-xl -tracking-[.015em]') { 'Route map' }
        span(class: 'board-meta') do
          "#{@board.event.name} · #{@board.event.start_time&.strftime('%a %-d %b %-l:%M %p')}"
        end
      end
      div(class: 'flex-1')
      a(href: "/board?event_id=#{@board.event.id}", class: 'board-btn no-underline text-ink') do
        'Back to the board'
      end
    end
  end

  # "Nothing to draw" with no cause is indistinguishable from a broken page,
  # which is exactly how the first version of this was read.
  EMPTY_REASONS = {
    no_drivers: 'Nobody is driving this one yet, so there are no routes to draw.',
    nobody_seated: 'No rider has been seated in a car yet — a route needs somewhere to collect ' \
                   'someone. Seat people on the board, or press Auto-fill.',
    no_locations: 'None of the pickups have a location on file yet. Add a street address on Locations.'
  }.freeze

  def empty_note
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[13px] text-ink/70') do
      plain EMPTY_REASONS[@map.empty_reason]
    end
  end

  # Colours carry identity, so every route is also named in the legend and its
  # stops numbered — never colour alone.
  def figure
    div(class: 'flex flex-col gap-3') do
      canvas
      legend
    end
  end

  # The payload rides on the element rather than being fetched, so the page is
  # one request and the map needs no second round trip.
  def canvas
    div(
      data_route_map: true,
      data_routes: @map.to_json_payload.to_json,
      data_venue: @map.venue_payload.to_json,
      data_tiles: @tiles[:url],
      data_attribution: @tiles[:attribution],
      class: 'h-[520px] w-full rounded-lg border border-line overflow-hidden bg-surface-sunk'
    ) do
      # Replaced by Leaflet on load; shown if the bundle fails or JS is off.
      div(class: 'flex items-center justify-center h-full text-[13px] text-ink/55') do
        'Loading the map…'
      end
    end
  end

  def legend
    div(class: 'flex flex-wrap gap-x-4 gap-y-1.5 px-1') do
      @map.drawn_routes.each_with_index do |route, i|
        div(class: 'flex items-center gap-1.5 text-[12px]') do
          span(class: 'w-3.5 h-3.5 rounded-full shrink-0',
               style: "background: #{@map.colour_for(i)}")
          span(class: 'capitalize') { route.name }
          span(class: 'text-ink/55') { "· #{route.pickups.size} #{'stop'.pluralize(route.pickups.size)}" }
        end
      end

      div(class: 'flex items-center gap-1.5 text-[12px]') do
        span(class: 'w-3.5 h-3.5 rounded-sm shrink-0 bg-ink')
        span { 'where everyone is going' }
      end
    end
  end

  # Named, not dropped. A pin missing from the picture is something to go and
  # fix, and it cannot be fixed if it is invisible.
  def unplotted_note
    div(class: 'p-3 rounded-lg border border-warn/30 bg-warn-tint text-[12.5px] text-warn-ink') do
      plain 'Not on the map — no location on file: '
      plain @map.unplotted.map { |s| s.name.presence || s.label }.compact.join(', ')
      plain '. Add a street address on '
      a(href: '/locations', class: 'underline') { 'Locations' }
      plain ', or a pickup spot in their details.'
    end
  end
end
