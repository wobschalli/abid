require_relative 'components/master'

class SeriesIndex < Phlex::HTML
  include Components

  DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  # @param series [Array<EventSeries>]
  # @param upcoming [Hash{Integer => Array<Event>}] next few occurrences per series
  def initialize(series:, upcoming:, breaks: [], leader: false, error: nil)
    @series = series
    @upcoming = upcoming
    @breaks = breaks
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: 'Recurring series', leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        header
        p(role: 'alert', class: 'text-sm text-danger') { @error } if @error
        if @series.empty?
          empty_note
        else
          div(class: 'flex flex-col gap-3') { @series.each { |s| card(s) } }
        end
        breaks_section
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

  # --- academic breaks ------------------------------------------------------

  def breaks_section
    div(class: 'flex flex-col gap-2.5 pt-2 border-t border-line') do
      div(class: 'flex items-baseline gap-2 pt-2') do
        span(class: 'board-label') { 'Academic breaks' }
        span(class: 'text-[11.5px] text-ink/60') { 'no occurrences are generated on these dates' }
      end

      if @breaks.empty?
        div(class: 'px-1 py-3 text-[13px] text-ink/65') do
          'None set. Without these the bot keeps posting sign-ups through winter break.'
        end
      else
        div(class: 'flex flex-col gap-1.5') { @breaks.each { |b| break_row(b) } }
      end

      add_break_form if @leader
    end
  end

  def break_row(academic_break)
    div(class: "flex items-center gap-3 px-3 py-2 rounded-lg border border-line bg-surface #{academic_break.past? ? 'opacity-55' : ''}") do
      span(class: 'flex-1 min-w-0 text-[12.5px] font-medium') { academic_break.name }
      span(class: 'board-meta whitespace-nowrap') { "#{academic_break.range_label} · #{academic_break.days} days" }
      next unless @leader

      form(method: 'post', action: "/breaks/#{academic_break.id}", class: 'contents') do
        input(type: 'hidden', name: '_method', value: 'delete')
        button(type: 'submit', title: 'Remove',
               class: 'border-0 bg-transparent text-ink/55 hover:text-danger font-mono text-xs font-semibold cursor-pointer px-1') do
          '✕'
        end
      end
    end
  end

  def add_break_form
    form(method: 'post', action: '/breaks', class: 'flex gap-2 items-end flex-wrap pt-1') do
      div(class: 'flex flex-col gap-[5px] flex-1 min-w-[180px]') do
        span(class: 'board-label') { 'Name' }
        input(type: 'text', name: 'name', required: true, placeholder: 'Spring break',
              class: 'board-input text-[12.5px] py-2')
      end
      div(class: 'flex flex-col gap-[5px]') do
        span(class: 'board-label') { 'From' }
        input(type: 'date', name: 'starts_on', required: true, class: 'board-input text-[12.5px] py-2')
      end
      div(class: 'flex flex-col gap-[5px]') do
        span(class: 'board-label') { 'To' }
        input(type: 'date', name: 'ends_on', required: true, class: 'board-input text-[12.5px] py-2')
      end
      button(type: 'submit', class: 'board-btn') { 'Add break' }
    end
  end
end
