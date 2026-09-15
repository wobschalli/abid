require_relative 'components/master'

class SeriesIndex < Phlex::HTML
  include Components

  DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  # @param series [Array<EventSeries>]
  # @param upcoming [Hash{Integer => Array<Event>}] next few occurrences per series
  def initialize(series:, upcoming:, leader: false)
    @series = series
    @upcoming = upcoming
    @leader = leader
  end

  def view_template
    Layout(title: 'Recurring series', leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        header
        if @series.empty?
          empty_note
        else
          div(class: 'flex flex-col gap-3') { @series.each { |s| card(s) } }
        end
      end
    end
  end

  private

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Recurring series' }
      div(class: 'flex-1')
      a(href: '/events', class: 'board-btn no-underline') { 'All events' }
      a(href: '/series/new', class: 'board-btn-solid no-underline') { 'New series' } if @leader
    end
  end

  def empty_note
    div(class: 'px-1 py-6 text-[13px] leading-relaxed text-ink/65') do
      plain 'No recurring series yet. Create one for each weekly slot — Sunday School, '
      plain 'Sunday Service, Friday study — and its occurrences will be generated automatically.'
    end
  end

  def card(series)
    div(class: 'flex flex-col gap-2.5 p-3.5 rounded-lg border border-line bg-surface') do
      div(class: 'flex items-center gap-2.5 flex-wrap') do
        a(href: "/series/#{series.id}", class: 'font-semibold text-[14px] text-ink no-underline hover:text-accent') do
          series.display_name
        end
        render Components::EventBadge.new(series: series)
        div(class: 'flex-1')
        generate_button(series) if @leader
        a(href: "/series/#{series.id}/edit", class: 'board-btn no-underline') { 'Edit' } if @leader
      end

      span(class: 'board-meta') { cadence(series) }
      next_occurrences(series)
    end
  end

  def cadence(series)
    return 'No weekday set — nothing will be generated' unless series.recurring?

    bits = ["#{DAYS[series.weekday]}s at #{series.start_time_of_day.strftime('%-l:%M %p')}"]
    bits << series.location.name if series.location
    bits << "posts #{series.message_lead_hours}h ahead"
    bits.join(' · ')
  end

  def next_occurrences(series)
    events = @upcoming[series.id] || []
    return span(class: 'text-[12px] text-ink/60') { 'No occurrences generated yet.' } if events.empty?

    div(class: 'flex flex-wrap gap-1.5') do
      events.each do |event|
        a(
          href: "/events/#{event.id}",
          class: 'font-mono text-[11px] px-2 py-1 rounded-md border border-line bg-surface-sunk no-underline text-ink/80 hover:border-accent'
        ) { event.start_time.strftime('%-d %b') }
      end
    end
  end

  def generate_button(series)
    form(method: 'post', action: "/series/#{series.id}/generate", class: 'contents') do
      button(type: 'submit', class: 'board-btn') { 'Generate now' }
    end
  end
end
