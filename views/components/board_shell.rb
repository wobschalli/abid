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

  def initialize(board:, can_undo: false, leader: false, tab: :details)
    @board = board
    @event = board.event
    @can_undo = can_undo
    @leader = leader
    @tab = tab
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
      event_nav
      div(class: 'font-display font-bold text-lg -tracking-[.015em]') { header_date }
      slot_tabs
      div(class: 'flex-1')
      undo_button
      sync_button if @leader
      a(
        href: "/board/#{@event.id}/map",
        class: 'board-btn no-underline text-ink'
      ) { 'Map' }
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

  # Step to the occurrence either side of this one, in time order.
  #
  # Until this existed there was no way to reach another day's board from the
  # board at all — you had to go back to Events and click. The control that sat
  # here was "+ slot", which looked like navigation and actually created an
  # event.
  #
  # Deliberately outside the tab group: `slot_tabs` returns early on a day with
  # nothing to switch between, which would take these with it.
  def event_nav
    div(class: 'flex items-center gap-1 -ml-1') do
      step_link(@board.previous_event, '‹', 'Previous ride')
      step_link(@board.next_event, '›', 'Next ride')
    end
  end

  # Rendered as a dead span rather than omitted when there is nowhere to go, so
  # the header does not reflow at either end of the calendar.
  def step_link(target, glyph, label)
    shape = 'flex items-center justify-center w-8 h-8 rounded-md ' \
            'text-[22px] leading-none pb-[3px] no-underline border border-transparent'
    if target.nil?
      span(class: "#{shape} text-ink/20", aria_hidden: 'true') { glyph }
    else
      a(href: "/board?event_id=#{target.id}",
        class: "#{shape} text-ink/60 hover:text-ink hover:bg-ink/5 hover:border-line",
        title: "#{label}: #{target.start_time&.strftime('%a %-d %b, %-l:%M %p')}",
        aria_label: label) { glyph }
    end
  end

  # One tab per event on this date — "Sunday School 9:30 AM" in the design.
  # Only when there is a choice to make: a single tab is just the page you are
  # already looking at.
  def slot_tabs
    siblings = @board.sibling_events
    return if siblings.size < 2

    div(class: 'flex gap-1 p-[3px] bg-ink/5 rounded-lg') do
      siblings.each { |sibling| slot_tab(sibling) }
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

  def undo_button
    action_form('undo', class: 'contents') do
      button(
        type: 'submit',
        class: "board-btn #{@can_undo ? '' : 'opacity-55'}",
        disabled: !(@can_undo && @leader)
      ) { 'Undo' }
    end
  end

  # Auto-fill is always closest-first. There used to be a strategy dropdown
  # next to this button; it made you answer a question before you could press
  # the thing you came to press, and the alternative only differed once zones
  # already matched.
  def autofill_form
    action_form('autofill', class: 'contents') do
      button(type: 'submit', class: 'board-btn-solid whitespace-nowrap') do
        plain 'Auto-fill'
        whitespace
        plain @board.pool_count.to_s
      end
    end
  end

  # Reactions arrive after the sign-up is posted, and a gateway event can be
  # dropped. This asks the bot to re-read them from Discord.
  #
  # It cannot show the result: the web process has no Discord connection, so
  # this sets a flag the bot picks up within 15 seconds. Saying "syncing…"
  # until it lands is the honest version — the alternative is a button that
  # looks like it did nothing.
  def sync_button
    if @board.sync_pending?
      return span(class: 'board-btn opacity-60 cursor-default',
                  title: 'the bot re-reads reactions within 15 seconds') { 'Syncing…' }
    end

    div(class: 'flex items-center gap-1.5') do
      action_form('resync', class: 'contents') do
        button(type: 'submit', class: 'board-btn whitespace-nowrap',
               title: 'Re-read this date\'s sign-up reactions from Discord') { 'Sync from Discord' }
      end
      sync_result
    end
  end

  # The outcome of the last sweep. "No changes" and "could not reach the
  # message" look identical without this, and they mean opposite things.
  def sync_result
    post = @board.last_sync
    return if post.nil?

    failed = post.reconcile_ok == false
    span(
      title: "last synced #{post.reconciled_at.strftime('%-l:%M %p')}",
      class: "text-[11px] whitespace-nowrap #{failed ? 'text-danger font-medium' : 'text-ink/55'}"
    ) { failed ? "⚠ #{post.reconcile_note}" : post.reconcile_note.to_s }
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
    div(class: 'col-span-full p-8 text-center text-ink/65 text-[13px] leading-relaxed flex flex-col items-center gap-3') do
      span do
        plain 'Nobody is driving yet. Reactions arrive as riders — the emoji does not say '
        plain 'which someone meant — so say who is driving here.'
      end
      add_drivers_button if @leader
      span(class: 'text-[12px] text-ink/55') do
        'Or switch anyone already on the board to Driving in their details.'
      end
    end
  end

  # The app already knows who drives: an active member with a seat count. This
  # saves adding the same handful of people by hand on every board, every week.
  # Confirmed, because it writes a row for every driver in one press. It fired
  # twice on this board without a deliberate click and the cause was never
  # pinned down — a bulk write should need a yes regardless.
  def add_drivers_button
    count = @board.regular_driver_count
    return if count.zero?

    action_form('drivers', class: 'contents') do
      button(type: 'submit', class: 'board-btn-solid',
             data_confirm: "Add #{count} regular drivers to this board?") do
        "Add the #{count} regular drivers"
      end
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
