require_relative 'components/master'

# The routes for one occurrence, drawn on a real basemap.
#
# It answers one question the car columns cannot: does this look sane, or is a
# driver crossing town twice to collect someone who is plainly on another
# driver's way? The optimizer works in driving minutes it cannot show you, so
# this is where its answer becomes something you can actually judge.
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
        empty_note if @map.empty_reason
        @map.any? ? figure : nothing_at_all
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
      a(href: path("/board?event_id=#{@board.event.id}"), class: 'board-btn no-underline text-ink') do
        'Back to the board'
      end
    end
  end

  # Why there are no LINES. Shown above the map rather than instead of it: the
  # map itself is still worth having — where people are waiting is the thing you
  # need in order to seat them — and swapping it for a paragraph made the page
  # read as broken, which is exactly how it was reported.
  EMPTY_REASONS = {
    no_drivers: 'No routes yet — nobody is driving this one. The pins below are where people ' \
                'are waiting, and where you are all going.',
    nobody_seated: 'No routes yet — nobody has been seated in a car. The pins below are where ' \
                   'people are waiting; seat them on the board, or press Optimize.',
    no_locations: 'No routes yet — none of the pickups have a location on file. Add a street ' \
                  'address on Locations.'
  }.freeze

  def empty_note
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[13px] text-ink/70') do
      plain EMPTY_REASONS[@map.empty_reason]
    end
  end

  # Genuinely nothing with coordinates — not even the venue.
  def nothing_at_all
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[13px] text-ink/70') do
      plain 'Nothing on this board has a location on file yet, so there is nothing to put on a map.'
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
      data_waiting: @map.waiting_payload.to_json,
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

      if @map.waiting.any?
        div(class: 'flex items-center gap-1.5 text-[12px]') do
          span(class: 'w-3.5 h-3.5 rounded-full shrink-0 border-2 border-dashed border-ink/45')
          span { "waiting for a ride · #{@map.waiting.size}" }
        end
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
      a(href: path('/locations'), class: 'underline') { 'Locations' }
      plain ', or a pickup spot in their details.'
    end
  end
end
