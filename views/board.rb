require_relative 'components/master'

# The ride board page. `fragment` returns just the swappable inner region, which
# is what the mutation routes hand back to the browser.
class Board < Phlex::HTML
  include Components

  def initialize(board:, can_undo: false, leader: false, tab: :details)
    @board = board
    @can_undo = can_undo
    @leader = leader
    @tab = tab
  end

  def fragment
    shell
  end

  def view_template
    Layout(title: "Rides — #{@board.event.display_name}", leader: @leader, full_bleed: true) do
      render shell
    end
  end

  private

  def shell
    Components::BoardShell.new(
      board: @board,
      can_undo: @can_undo,
      leader: @leader,
      tab: @tab
    )
  end
end
