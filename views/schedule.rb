require_relative 'components/master'

# Events, Series and Sign-ups used to be three pages answering the same question
# at three zoom levels, with three different filters over the same rows and
# cross-links between their headers. They are one page now, organised by date,
# because "what is coming up and is it sorted?" is the only question a rides
# coordinator actually asks.
#
# The recurring templates sit in a collapsed section at the bottom: they are set
# once a semester, so they are reference material rather than the daily view.
class Schedule < Phlex::HTML
  include Components

  def initialize(dates:, series:, breaks:, past: [], leader: false, error: nil)
    @dates = dates
    @series = series
    @breaks = breaks
    @past = past
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: 'Schedule', leader: @leader) do
      div(class: 'max-w-3xl flex flex-col gap-5 font-sans text-ink') do
        header
        p(role: 'alert', class: 'text-sm text-danger') { @error } if @error
        @dates.empty? ? empty_note : upcoming
        recurring_section
        past_section
      end
    end
  end

  private

  # Adding an event is a top-level action, so it lives in the header rather than
  # folded inside the recurring section — which is collapsed by default, and is
  # about the templates rather than about creating anything.
  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Schedule' }
      span(class: 'board-meta') { "#{@dates.size} dates coming up" }
      div(class: 'flex-1')
      new_event_actions if @leader
    end
  end

  def new_event_actions
    div(class: 'flex gap-2 flex-wrap') do
      a(href: '/events/new', class: 'board-btn-solid no-underline') { 'New event' }
      a(href: '/series/new', class: 'board-btn no-underline text-ink') { 'New recurring event' }
    end
  end

  def empty_note
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[13px] text-ink/70') do
      'Nothing coming up. Add a recurring event above and its occurrences — and their sign-ups — appear on their own.'
    end
  end

  # --- what is coming up ----------------------------------------------------

  def upcoming
    div(class: 'flex flex-col gap-2.5') { @dates.each { |day| date_card(day) } }
  end

  def date_card(day)
    div(class: 'flex flex-col rounded-lg border border-line bg-surface overflow-hidden') do
      div(class: 'flex items-baseline gap-2 px-3.5 pt-3 pb-1') do
        span(class: 'font-display font-bold text-[15px]') { day.date.strftime('%A %-d %B') }
        span(class: 'board-meta') { relative_label(day.date) }
      end

      div(class: 'flex flex-col') { day.events.each { |event| event_row(event) } }
      signup_row(day)
    end
  end

  def event_row(event)
    a(href: "/board?event_id=#{event.id}",
      class: 'flex items-center gap-3 px-3.5 py-2 no-underline text-ink hover:bg-surface-sunk') do
      span(class: 'font-mono text-[11.5px] text-ink/70 w-[68px] shrink-0') do
        event.start_time&.strftime('%-l:%M %p').to_s
      end
      span(class: 'flex-1 min-w-0 text-[13px] font-medium') { event.name.to_s }
      render Components::EventBadge.new(event: event) if event.disabled
      span(class: 'board-meta whitespace-nowrap') { roster(event) }
    end
  end

  def roster(event)
    riders = event.rides.count { |r| r.role == 'rider' }
    cars = event.rides.count { |r| r.role == 'driver' }
    # Not "no sign-ups" — that reads as a comment on the sign-up post one line
    # below, which may well have been sent.
    return 'nobody yet' if riders.zero? && cars.zero?

    [("#{riders} riders" if riders.positive?), ("#{cars} cars" if cars.positive?)].compact.join(' · ')
  end

  # The line that used to be a whole separate page.
  def signup_row(day)
    post = day.post
    div(class: 'flex items-center gap-2 px-3.5 py-2 border-t border-line-soft bg-surface-sunk flex-wrap') do
      span(class: 'board-label') { 'Sign-up' }
      post ? signup_state(post) : span(class: 'text-[12px] text-warn-ink') { 'none yet' }
      div(class: 'flex-1')
      post ? a(href: "/signups/#{post.id}", class: 'board-btn no-underline text-ink') { 'Open' }
           : create_signup(day)
    end
  end

  def signup_state(post)
    span(class: 'text-[12px]') do
      case post.status
      when 'posted'
        plain post.closed_at ? 'closed' : 'posted'
        whitespace
        span(class: 'text-ink/60') { "· #{post.reaction_count} reactions" }
      when 'scheduled'
        plain 'sends '
        strong { post.post_at.strftime('%a %-d %b, %-l:%M %p') }
      when 'failed'
        span(class: 'text-danger') { 'failed to send' }
      else
        span(class: 'text-warn-ink') { 'draft — not scheduled' }
      end
    end
  end

  def create_signup(day)
    return unless @leader

    form(method: 'post', action: '/signups', class: 'contents') do
      input(type: 'hidden', name: 'service_date', value: day.date.strftime('%Y-%m-%d'))
      input(type: 'hidden', name: 'channel_id', value: day.channel_id)
      button(type: 'submit', class: 'board-btn') { 'Create' }
    end
  end

  def relative_label(date)
    days = (date - Time.zone.today).to_i
    case days
    when 0 then 'today'
    when 1 then 'tomorrow'
    else "in #{days} days"
    end
  end

  # --- recurring templates, set once a semester -----------------------------

  def recurring_section
    details(class: 'rounded-lg border border-line bg-surface') do
      summary(class: 'cursor-pointer px-3.5 py-2.5 text-[13px] font-semibold select-none') do
        plain 'Recurring events'
        whitespace
        span(class: 'text-ink/55 font-normal') { "· #{@series.size} · set once a semester" }
      end

      div(class: 'flex flex-col gap-3 px-3.5 pb-3.5 pt-1') do
        @series.each { |s| series_row(s) }
        series_actions if @leader
        breaks_section
      end
    end
  end

  def series_row(s)
    a(href: "/series/#{s.id}",
      class: 'flex items-center gap-3 px-3 py-2 rounded-lg border border-line no-underline text-ink hover:border-accent') do
      span(class: 'flex-1 min-w-0 flex flex-col gap-0.5') do
        span(class: 'text-[13px] font-medium') { s.display_name }
        span(class: 'board-meta') { cadence(s) }
      end
      span(class: 'board-meta whitespace-nowrap') { s.disabled ? 'disabled' : '' }
    end
  end

  def cadence(s)
    return 'No weekday set — nothing will be generated' unless s.recurring?

    [
      "#{Date::DAYNAMES[s.weekday]}s at #{s.start_time_of_day.strftime('%-l:%M %p')}",
      s.location&.name,
      s.signup_schedule_label
    ].compact.join(' · ')
  end

  def series_actions
    div(class: 'flex gap-2 flex-wrap') { generate_button }
  end

  # Occurrences are materialised daily by the bot, and creating or editing a
  # series does it immediately — so this is only of use when the bot has been
  # off. Saying so stops it reading as a step someone has to remember.
  def generate_button
    form(method: 'post', action: '/schedule/generate', class: 'contents') do
      button(type: 'submit', class: 'board-btn',
             title: 'Normally automatic — use this if the bot has been offline') { 'Generate now' }
    end
  end

  def breaks_section
    div(class: 'flex flex-col gap-2 pt-2 border-t border-line') do
      div(class: 'flex items-baseline gap-2 pt-1') do
        span(class: 'board-label') { 'Academic breaks' }
        span(class: 'text-[11.5px] text-ink/60') { 'no occurrences are generated on these dates' }
      end

      if @breaks.empty?
        div(class: 'px-1 py-2 text-[12.5px] text-ink/65') do
          'None set. Without these the bot keeps posting sign-ups through winter break.'
        end
      else
        div(class: 'flex flex-col gap-1.5') { @breaks.each { |b| break_row(b) } }
      end

      add_break_form if @leader
    end
  end

  def break_row(academic_break)
    div(class: "flex items-center gap-3 px-3 py-2 rounded-lg border border-line #{academic_break.past? ? 'opacity-55' : ''}") do
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
      div(class: 'flex flex-col gap-[5px] flex-1 min-w-[160px]') do
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

  # --- history --------------------------------------------------------------

  def past_section
    return if @past.empty?

    details(class: 'rounded-lg border border-line bg-surface') do
      summary(class: 'cursor-pointer px-3.5 py-2.5 text-[13px] font-semibold select-none') do
        plain 'Past events'
        whitespace
        span(class: 'text-ink/55 font-normal') { "· #{@past.size}" }
      end
      div(class: 'px-2 pb-3') { render Components::EventTable.new(events: @past) }
    end
  end
end
