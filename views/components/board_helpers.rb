require 'uri'
require_relative 'components'

# Shared bits between the board components: link building that preserves the
# current filter/selection/tab, and the "fit" pill styling from the design.
module BoardHelpers
  # Every board link round-trips the view state so a no-JS click doesn't drop
  # the search box contents or which person is open in the rail.
  def board_url(**overrides)
    query = {
      event_id: @board.event.id,
      q: @board.query.presence,
      tab: (@tab == :roster ? 'roster' : nil),
      sel: @board.selected_ride_id,
      focus: @board.focus_ride_id
    }.merge(overrides).compact

    "/board?#{URI.encode_www_form(query)}"
  end

  def endpoint(path)
    "/board/#{@board.event.id}/#{path}"
  end

  FIT_PILLS = {
    clash: 'bg-danger-tint text-danger',
    full: 'bg-ink/[.07] text-ink/70',
    closest: 'bg-ink text-ink-invert',
    space: 'bg-accent-tint text-accent'
  }.freeze

  FIT_LABELS = {
    clash: 'clash',
    full: 'full',
    closest: 'closest',
    space: 'space'
  }.freeze

  def fit_pill_class(fit)
    "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] #{FIT_PILLS[fit]}"
  end

  # A small POST form, since the board's actions are all state changes and the
  # page has to keep working when the JS hasn't loaded.
  def action_form(path, method: 'post', **fields, &block)
    form(
      method: 'post',
      action: endpoint(path),
      data_board_form: true,
      class: fields.delete(:class) || 'contents'
    ) do
      input(type: 'hidden', name: '_method', value: method) unless method == 'post'
      input(type: 'hidden', name: 'q', value: @board.query) if @board.query.present?
      input(type: 'hidden', name: 'tab', value: 'roster') if @tab == :roster
      fields.each do |name, value|
        input(type: 'hidden', name: name.to_s, value: value.to_s)
      end
      yield
    end
  end
end
