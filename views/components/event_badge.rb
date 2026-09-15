require_relative 'components'

# Small pill: how an event recurs, and whether it is switched off.
class Components::EventBadge < Phlex::HTML
  BASE = 'font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase'.freeze

  def initialize(event: nil, series: nil)
    @event = event
    @series = series
  end

  def view_template
    span(class: "#{BASE} #{style}") { label }
  end

  private

  def disabled?
    (@series || @event)&.disabled
  end

  def label
    return 'disabled' if disabled?
    return cadence if @series
    @event.recurring? ? 'weekly' : 'one-off'
  end

  def style
    return 'bg-ink/[.07] text-ink/70' if disabled?
    return 'bg-accent-tint text-accent' if @series || @event&.recurring?

    'bg-ink/[.07] text-ink/70'
  end

  def cadence
    weeks = @series.interval_weeks.to_i
    return 'weekly' if weeks <= 1
    return 'fortnightly' if weeks == 2

    "every #{weeks} wks"
  end
end
