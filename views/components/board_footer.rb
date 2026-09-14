require_relative 'components'

# Status strip: unresolved problems on the left, tallies on the right.
class Components::BoardFooter < Phlex::HTML
  def initialize(board:)
    @board = board
  end

  def view_template
    div(class: 'flex-none flex items-center gap-4 px-5 py-[11px] border-t border-line bg-surface-sunk flex-wrap') do
      warnings if @board.warnings.any?
      div(class: 'flex-1')
      counts
    end
  end

  private

  def warnings
    div(class: 'flex items-center gap-2 font-medium text-xs text-warn-ink') do
      span(class: 'w-1.5 h-1.5 rounded-full bg-warn flex-none')
      plain @board.warning_text
    end
  end

  def counts
    div(class: 'flex items-center gap-2 font-mono font-medium text-[11.5px] text-ink/70') do
      span { "#{@board.seated_count} seated" }
      span(class: 'opacity-35') { '·' }
      span { "#{@board.pool_count} waiting" }
      span(class: 'opacity-35') { '·' }
      span { "#{@board.seats_left} seats open" }
    end
  end
end
