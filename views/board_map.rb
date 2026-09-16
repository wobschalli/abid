require_relative 'components/master'

# The routes for one occurrence, drawn.
#
# It answers one question — does this look sane? — that the car columns cannot:
# whether a driver is crossing town twice, or collecting someone who is plainly
# on another driver's way. Auto-fill sorts by zone, which is a coarse proxy for
# geography, so this is where you catch it doing something daft.
class BoardMap < Phlex::HTML
  include Components

  # Categorical slots, assigned in fixed order and never cycled — a route's
  # colour must not change because a different driver was added. The values
  # live in application.css so light and dark swap in one place; both sets are
  # validated against their own surface.
  SERIES = 6

  def initialize(board:, map:, leader: false)
    @board = board
    @map = map
    @leader = leader
  end

  def view_template
    Layout(title: "Map — #{@board.event.name}", leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-4 font-sans text-ink') do
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

  # Say which of the three reasons it is. "Nothing to draw" with no cause is
  # indistinguishable from a broken page.
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
      div(class: 'rounded-lg border border-line bg-surface p-2 overflow-x-auto') { canvas }
      legend
    end
  end

  def canvas
    render Components::RouteCanvas.new(map: @map, event: @board.event,
                                       colour: method(:colour))
  end

  def legend
    div(class: 'flex flex-wrap gap-x-4 gap-y-1.5 px-1') do
      @map.drawn_routes.each do |route|

        div(class: 'flex items-center gap-1.5 text-[12px]') do
          span(class: 'w-3.5 h-3.5 rounded-full shrink-0',
               style: "background: #{colour(route.slot)}")
          span(class: 'capitalize') { route.name }
          span(class: 'text-ink/55') { "· #{route.pickups.size} stops" }
        end
      end

      div(class: 'flex items-center gap-1.5 text-[12px]') do
        span(class: 'w-3.5 h-3.5 rounded shrink-0 bg-ink')
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

  # A seventh driver would be a seventh hue nobody can tell from the first, so
  # everyone past the palette shares one muted slot and is told apart by the
  # numbered stops and the legend instead.
  def colour(slot)
    return 'var(--color-ink)' if slot >= SERIES

    "var(--color-series-#{slot + 1})"
  end
end
