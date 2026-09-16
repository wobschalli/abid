require_relative 'components/master'

# One occurrence. Upcoming events link to the live board; past ones show their
# final roster, frozen.
class EventShow < Phlex::HTML
  include Components

  def initialize(event:, board:, leader: false)
    @event = event
    @board = board
    @leader = leader
  end

  def view_template
    Layout(title: @event.display_name, leader: @leader) do
      div(class: 'max-w-5xl flex flex-col gap-5 font-sans text-ink') do
        breadcrumb
        header
        facts
        roster
      end
    end
  end

  private

  def past?
    @event.end_time_or_estimate <= Time.zone.now
  end

  def breadcrumb
    div(class: 'text-[12px] text-ink/60') do
      a(href: '/schedule', class: 'text-accent no-underline hover:underline') { 'Schedule' }
      plain ' / '
      plain @event.name.to_s
    end
  end

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      div(class: 'flex flex-col gap-1') do
        div(class: 'flex items-baseline gap-2.5 flex-wrap') do
          h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { @event.name.to_s }
          render Components::EventBadge.new(event: @event)
        end
        span(class: 'board-meta') { when_label }
      end

      div(class: 'flex-1')

      a(href: "/events/#{@event.id}.csv", class: 'board-btn no-underline') { 'Export .csv' }
      if past?
        a(href: "/board?event_id=#{@event.id}", class: 'board-btn no-underline') { 'Open board' }
      else
        a(href: "/board?event_id=#{@event.id}", class: 'board-btn-solid no-underline') { 'Open ride board' }
      end
      a(href: "/events/#{@event.id}/edit", class: 'board-btn no-underline') { 'Edit' } if @leader
    end
  end

  def when_label
    return 'No date set' if @event.start_time.nil?

    label = @event.start_time.strftime('%A %-d %B %Y · %-l:%M %p')
    label += " – #{@event.end_time.strftime('%-l:%M %p')}" if @event.end_time
    label
  end

  def facts
    div(class: 'grid gap-3 grid-cols-[repeat(auto-fit,minmax(160px,1fr))]') do
      fact('Section', @event.section.presence || '—')
      fact('Location', @event.location&.name || '—')
      fact('Channel', @event.channel&.name || '—')
      fact('Series', series_link)
      fact('Sign-up', @event.posted? ? 'posted' : 'not sent yet')
    end
  end

  def fact(label, value)
    div(class: 'flex flex-col gap-1 p-3 rounded-lg border border-line bg-surface-sunk') do
      span(class: 'board-label') { label }
      if value.is_a?(Proc)
        value.call
      else
        span(class: 'text-[13px]') { value.to_s }
      end
    end
  end

  def series_link
    series = @event.series
    return '—' if series.nil?

    -> {
      a(href: "/series/#{series.id}", class: 'text-[13px] text-accent no-underline hover:underline') do
        series.display_name
      end
    }
  end

  def roster
    div(class: 'flex flex-col gap-2.5') do
      div(class: 'flex items-baseline gap-2') do
        span(class: 'board-label') { past? ? 'Final roster' : 'Roster so far' }
        unless past?
          span(class: 'text-[11.5px] text-ink/60') { 'still editable on the ride board' }
        end
      end
      render Components::RosterSnapshot.new(board: @board)
    end
  end
end
