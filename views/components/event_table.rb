require_relative 'components'
require_relative 'event_badge'

# A list of event occurrences. Used by the events index and by a series' own
# page, so the roster counts come preloaded either way.
class Components::EventTable < Phlex::HTML
  def initialize(events:, empty: 'Nothing here yet.')
    @events = events
    @empty = empty
  end

  def view_template
    return empty_note if @events.empty?

    div(class: 'flex flex-col gap-1.5') do
      @events.each { |event| row(event) }
    end
  end

  private

  def empty_note
    div(class: 'px-1 py-6 text-[13px] text-ink/65') { @empty }
  end

  def row(event)
    a(
      href: path("/events/#{event.id}"),
      class: 'flex items-center gap-3 px-3 py-2.5 rounded-lg border border-line bg-surface ' \
             'no-underline text-ink hover:border-accent transition-colors'
    ) do
      div(class: 'w-28 flex-none font-mono text-[11px] text-ink/70') { date_label(event) }

      div(class: 'flex-1 min-w-0 flex flex-col gap-0.5') do
        div(class: 'flex items-baseline gap-2 flex-wrap') do
          span(class: 'font-semibold text-[13px]') { event.name.to_s }
          render Components::EventBadge.new(event: event)
        end
        span(class: 'board-meta') { meta(event) }
      end

      div(class: 'flex-none font-mono text-[11px] text-ink/70 text-right') { roster(event) }
    end
  end

  def date_label(event)
    return '—' if event.start_time.nil?

    "#{event.start_time.strftime('%a %-d %b')} · #{event.start_time.strftime('%-l:%M %p')}"
  end

  def meta(event)
    [
      event.location&.name,
      (event.posted? ? 'posted' : nil)
    ].compact.join(' · ')
  end

  def roster(event)
    riders = event.rides.count { |r| r.rider? && r.active? }
    drivers = event.rides.count { |r| r.driver? && r.active? }
    # "nobody yet", matching the schedule page for the identical condition.
    # This counts the ROSTER — calling it "no sign-ups" made dates whose
    # sign-up existed as a draft look unhandled.
    return 'nobody yet' if riders.zero? && drivers.zero?

    "#{riders} riders · #{drivers} cars"
  end
end
