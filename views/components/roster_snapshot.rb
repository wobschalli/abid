require_relative 'components'
require_relative 'board_footer'

# A past occurrence's final roster, read only.
#
# Deliberately NOT Components::BoardCar — that is drag-and-drop machinery with
# drop zones and action forms, and threading a `leader:`/`readonly:` flag through
# it would complicate the live board to serve a page that just needs to print
# names. It does reuse RideBoard::Car for the numbers, and BoardFooter verbatim,
# since that component is already pure output.
class Components::RosterSnapshot < Phlex::HTML
  def initialize(board:)
    @board = board
  end

  def view_template
    div(class: 'flex flex-col gap-4') do
      cars
      waiting if @board.pool.any?
      dropped if @board.out_riders.any?
      render Components::BoardFooter.new(board: @board)
    end
  end

  private

  def cars
    if @board.cars.empty?
      return div(class: 'px-1 py-6 text-[13px] text-ink/65') { 'Nobody drove for this event.' }
    end

    div(class: 'grid gap-3.5 grid-cols-[repeat(auto-fill,minmax(248px,1fr))] items-start') do
      @board.cars.each { |car| car_card(car) }
    end
  end

  def car_card(car)
    div(class: "flex flex-col bg-surface border #{car.over? ? 'border-warn' : 'border-line'} rounded-[10px]") do
      div(class: 'flex flex-col gap-0.5 px-3 pt-[11px] pb-[9px]') do
        span(class: 'font-bold text-sm capitalize') { car.name }
        span(class: 'board-meta') { "#{car.zone || 'no zone'} · #{car.seat_text}" }
      end

      div(class: 'h-[3px] flex-none mx-3 rounded-full bg-ink/[.12] overflow-hidden') do
        div(class: "h-full #{car.over? ? 'bg-warn' : 'bg-accent'}", style: "width: #{car.fill_percent}%")
      end

      div(class: 'mt-2.5') do
        car.passengers.each { |p| passenger(car, p) }
        if car.passengers.empty?
          div(class: 'px-3 pb-3 text-[11.5px] text-ink/60') { 'empty' }
        end
      end
    end
  end

  def passenger(_car, passenger)
    div(class: 'flex items-center gap-2 px-[11px] py-1.5 border-t border-line-soft') do
      div(class: 'flex-1 min-w-0 flex flex-col gap-px') do
        span(class: 'font-medium text-[12.5px] capitalize') { passenger.display_name }
        if passenger.address.present?
          span(class: 'text-[10.5px] text-ink/70 whitespace-nowrap overflow-hidden text-ellipsis') { passenger.address }
        end
      end
    end
  end

  def waiting
    listing('Never got a ride', @board.pool)
  end

  def dropped
    listing('Did not come', @board.out_riders, strike: true)
  end

  def listing(title, rides, strike: false)
    div(class: 'flex flex-col gap-1.5') do
      span(class: 'board-label') { title }
      div(class: 'flex flex-wrap gap-1.5') do
        rides.each do |ride|
          span(
            class: "text-[12px] capitalize px-2.5 py-1 rounded-full border border-line bg-surface #{strike ? 'line-through text-ink/60' : ''}"
          ) { ride.display_name }
        end
      end
    end
  end
end
