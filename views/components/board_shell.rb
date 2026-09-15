require_relative 'components'
require_relative 'board_helpers'

# The whole ride board, minus the app chrome. Rendered standalone by the
# mutation routes so the browser can swap this one element.
#
# Port of Ride Board.dc.html. The design's slot tabs are sibling Event rows on
# the same date; its `assign` map is rides.driver_ride_id.
class Components::BoardShell < Phlex::HTML
  include BoardHelpers

  ROOT_ID = 'ride-board'.freeze

  def initialize(board:, can_undo: false, leader: false, tab: :details, strategy: 'closest')
    @board = board
    @event = board.event
    @can_undo = can_undo
    @leader = leader
    @tab = tab
    @strategy = strategy
  end

  def view_template
    div(
      id: ROOT_ID,
      class: 'flex flex-col h-[calc(100vh-3.5rem)] min-h-[760px] bg-surface text-ink font-sans',
      data_board_root: true,
      data_event_id: @event.id,
      data_endpoint: "/board/#{@event.id}",
      data_readonly: (!@leader).to_s
    ) do
      board_header
      div(class: 'flex-1 flex min-h-0') do
        render Components::BoardQueue.new(board: @board, leader: @leader, tab: @tab)
        car_grid
        render Components::BoardRail.new(board: @board, leader: @leader, tab: @tab)
      end
      render Components::DispatchBar.new(board: @board, readiness: @board.readiness,
                                         status: @board.dispatch_status, leader: @leader, tab: @tab)
      render Components::BoardFooter.new(board: @board)
    end
  end

  private

  def board_header
    div(class: 'flex items-center gap-3.5 px-5 py-3.5 border-b border-line flex-none flex-wrap') do
      div(class: 'font-display font-bold text-lg -tracking-[.015em]') { header_date }
      slot_tabs
      div(class: 'flex-1')
      undo_button
      a(
        href: "/board/#{@event.id}.csv",
        class: 'board-btn no-underline text-ink'
      ) { 'Export .csv' }
      autofill_form if @leader
    end
  end

  def header_date
    (@event.start_time || Time.zone.now).strftime('%A %-d %b')
  end

  # One tab per event on this date — "Sunday School 9:30 AM" in the design.
  def slot_tabs
    siblings = @board.sibling_events
    return if siblings.empty?

    div(class: 'flex gap-1 p-[3px] bg-ink/5 rounded-lg') do
      siblings.each { |sibling| slot_tab(sibling) }
      new_slot_hint
    end
  end

  def slot_tab(sibling)
    current = sibling.id == @event.id
    classes = [
      'border-0 cursor-pointer font-semibold text-[11.5px] px-[11px] py-1.5 rounded-md no-underline',
      current ? 'bg-surface text-ink shadow-[0_1px_2px_rgba(23,32,28,.12)]' : 'bg-transparent text-ink/70 hover:text-ink'
    ].join(' ')

    a(href: "/board?event_id=#{sibling.id}", class: classes) do
      plain sibling.name.to_s
      whitespace
      span(class: 'opacity-70') { sibling.start_time&.strftime('%-l:%M %p').to_s }
    end
  end

  # `addSlot` is a no-op in the design. Event creation already lives in Discord,
  # so this points there rather than shipping a dead button.
  def new_slot_hint
    span(
      class: 'text-ink/45 font-medium text-xs px-2.5 py-1.5 cursor-default',
      title: 'Create events in Discord with /event create'
    ) { '+ slot' }
  end

  def undo_button
    action_form('undo', class: 'contents') do
      button(
        type: 'submit',
        class: "board-btn #{@can_undo ? '' : 'opacity-55'}",
        disabled: !(@can_undo && @leader)
      ) { 'Undo' }
    end
  end

  def autofill_form
    action_form('autofill', class: 'flex items-center gap-2') do
      select(
        name: 'strategy',
        class: 'board-input w-auto py-[7px] text-xs',
        aria_label: 'Auto-fill strategy'
      ) do
        AutoFiller::STRATEGIES.each do |value, label|
          option(value: value, selected: value == @strategy) { label }
        end
      end
      button(type: 'submit', class: 'board-btn-solid whitespace-nowrap') do
        plain 'Auto-fill'
        whitespace
        plain @board.pool_count.to_s
      end
    end
  end

  def car_grid
    div(class: 'flex-1 flex flex-col min-w-0') do
      selection_bar if @board.selected
      div(
        class: 'flex-1 overflow-y-auto p-4 grid gap-3.5 content-start bg-surface-board ' \
               'grid-cols-[repeat(auto-fill,minmax(248px,1fr))]'
      ) do
        @board.cars.each do |car|
          render Components::BoardCar.new(car: car, board: @board, leader: @leader, tab: @tab)
        end
        empty_board if @board.cars.empty?
      end
    end
  end

  def empty_board
    div(class: 'col-span-full p-8 text-center text-ink/65 text-[13px] leading-relaxed') do
      plain 'Nobody has volunteered to drive yet. Add a driver from the Roster tab, '
      plain 'or mark someone as driving in their details.'
    end
  end

  # The dark bar that appears while a rider is selected for seating.
  def selection_bar
    rider = @board.selected
    div(class: 'flex items-center gap-3 px-[18px] py-[11px] bg-ink text-ink-invert flex-none flex-wrap') do
      span(class: 'board-label !text-ink-invert/60') { 'Seating' }
      span(class: 'font-bold text-sm capitalize') { rider.display_name }
      span(class: 'font-mono text-[11.5px] opacity-60') { selection_meta(rider) }
      span(class: 'flex-1')
      span(class: 'text-[11.5px] opacity-65') { 'pick a car below' }
      a(
        href: board_url(sel: nil),
        class: 'border border-white/25 text-ink-invert font-semibold text-[11px] px-2.5 py-[5px] rounded-md no-underline hover:bg-white/10'
      ) { 'Cancel' }
    end
  end

  def selection_meta(rider)
    [rider.zone, rider.address].compact_blank.join(' · ')
  end
end
