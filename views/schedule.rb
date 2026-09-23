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

  def initialize(dates:, series:, breaks:, past: [], only_one_off: false, leader: false, error: nil)
    @dates = dates
    @only_one_off = only_one_off
    @series = series
    @breaks = breaks
    @past = past
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: 'Schedule', leader: @leader) do
      div(class: 'max-w-5xl flex flex-col gap-5 font-sans text-ink') do
        header
        p(role: 'alert', class: 'text-sm text-danger') { @error } if @error

        # The calendar is the shape of the term at a glance; the list is the
        # detail. Stacks on narrow screens with the list first, since that is
        # the one you act on.
        div(class: 'grid gap-5 lg:grid-cols-[1fr_248px] items-start') do
          div(class: 'flex flex-col gap-5 min-w-0') do
            @dates.empty? ? empty_note : upcoming
            recurring_section
            past_section
          end
          calendar
        end
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
      kind_filter
      div(class: 'flex-1')
      new_event_actions if @leader
    end
  end

  # The weekly rhythm is the thing you already know; a retreat is the thing you
  # are looking for. Hiding the recurring dates leaves just the exceptions.
  def kind_filter
    div(class: 'flex gap-1 p-[3px] bg-ink/5 rounded-lg') do
      kind_tab(nil, 'All')
      kind_tab('one_off', 'One-off only')
    end
  end

  def kind_tab(value, label)
    current = @only_one_off == (value == 'one_off')
    classes = [
      'border-0 cursor-pointer font-semibold text-[11.5px] px-[11px] py-1.5 rounded-md no-underline',
      current ? 'bg-surface text-ink shadow-[0_1px_2px_rgba(23,32,28,.12)]' : 'bg-transparent text-ink/70 hover:text-ink'
    ].join(' ')

    a(href: path(value ? "/schedule?only=#{value}" : '/schedule'), class: classes) { label }
  end

  def new_event_actions
    div(class: 'flex gap-2 flex-wrap') do
      a(href: path('/events/new'), class: 'board-btn-solid no-underline') { 'New event' }
      a(href: path('/series/new'), class: 'board-btn no-underline text-ink') { 'New recurring event' }
    end
  end

  def empty_note
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[13px] text-ink/70') do
      if @only_one_off
        'No one-off events coming up — just the weekly rhythm. Switch to All to see it.'
      else
        'Nothing coming up. Add a recurring event above and its occurrences — and their sign-ups — appear on their own.'
      end
    end
  end

  # --- calendar -------------------------------------------------------------
  #
  # Every month the upcoming dates span, so the term has a shape rather than
  # being a list you scroll. A day with rides is filled and links to its card.

  DAY_INITIALS = %w[S M T W T F S].freeze

  # Five months ahead, which spans six month grids: the rest of this one
  # through the month five months out.
  MONTHS_AHEAD = 5

  def calendar
    by_date = @dates.index_by(&:date)
    # Scrollable, not just sticky. Five month grids are taller than a laptop
    # viewport, so pinning the container left January and February rendered but
    # unreachable — you could scroll the list past them and never see them.
    div(class: 'flex flex-col gap-3 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto lg:pr-1') do
      months.each { |first| month_grid(first, by_date) }
      legend
    end
  end

  # Every month the five-month window touches, so the calendar covers exactly
  # what the list below it covers. Anything less and a date is in the list with
  # no cell to click.
  #
  # It used to run to the month of the LAST loaded date, so the calendar was
  # however long the query happened to be — three weeks of generated Fridays
  # meant a one-month calendar, and it looked like the term ended in October.
  # The span is the point: it should show the shape of the term whether or not
  # anything is on a given week yet.
  def months
    first = Time.zone.today.beginning_of_month
    last = (Time.zone.today + MONTHS_AHEAD.months).beginning_of_month
    out = []
    while first <= last
      out << first
      first = first.next_month
    end
    out
  end

  def month_grid(first, by_date)
    div(class: 'rounded-lg border border-line bg-surface p-3 flex flex-col gap-2') do
      div(class: 'font-display font-bold text-[13px]') { first.strftime('%B %Y') }

      div(class: 'grid grid-cols-7 gap-y-1 text-center') do
        DAY_INITIALS.each_with_index do |letter, i|
          span(class: 'font-mono text-[9.5px] text-ink/45 pb-1', key: i) { letter }
        end

        # Blank cells so the 1st lands under the right weekday.
        first.wday.times { span }

        (first..first.end_of_month).each { |date| day_cell(date, by_date[date]) }
      end
    end
  end

  # Three cases, all the same size so the seven-column grid never shifts.
  #
  # A day with rides goes to that day's sign-up, because that is the thing you
  # open a calendar to reach. It used to be an in-page anchor that scrolled to
  # the card below — fine when the list was six weeks long, useless once it is
  # five months and the card you want is forty rows down.
  def day_cell(date, day)
    return blank_cell(date) if day.nil?
    return post_link(date, day) if day.post

    create_cell(date, day)
  end

  def cell_classes(date, tone)
    today = date == Time.zone.today
    'flex items-center justify-center h-7 w-full text-[11.5px] rounded-md no-underline ' \
      "#{today ? 'ring-1 ring-accent font-bold' : ''} #{tone}"
  end

  def blank_cell(date)
    span(class: cell_classes(date, date < Time.zone.today ? 'text-ink/25' : 'text-ink/55')) do
      date.day.to_s
    end
  end

  def post_link(date, day)
    a(href: path("/signups/#{day.post.id}"), title: "#{day_title(day)} — open the sign-up",
      class: cell_classes(date, 'bg-accent-tint text-accent font-semibold hover:bg-accent-tint-strong')) do
      date.day.to_s
    end
  end

  # No sign-up for that date yet, so set one up and open it — seeded with that
  # day's emoji rows and scheduled for the usual send time, which is exactly
  # what the automation would do when the date came into range.
  #
  # A form rather than a link because it writes a row, and a GET that writes
  # gets fired by a browser prefetching what it thinks you are about to click.
  # Idempotent, so clicking twice opens the same post.
  def create_cell(date, day)
    return blank_cell(date) unless @leader

    form(method: 'post', action: path("/schedule/#{date.strftime('%Y-%m-%d')}/signup"), class: 'contents') do
      button(
        type: 'submit',
        title: "#{day_title(day)} — start the sign-up",
        class: "#{cell_classes(date, 'text-accent font-semibold border border-dashed border-accent/45 hover:bg-accent-tint')} " \
               'cursor-pointer bg-transparent'
      ) { date.day.to_s }
    end
  end

  def day_title(day)
    rides = day.events.map { |e| "#{e.start_time&.strftime('%-l:%M %p')} #{e.name}" }.join(', ')
    "#{day.date.strftime('%a %-d %b')} — #{rides}"
  end

  def legend
    div(class: 'flex flex-col gap-1 px-1 text-[11px] text-ink/60') do
      div(class: 'flex items-center gap-2') do
        span(class: 'w-4 h-4 rounded bg-accent-tint border border-accent/30 shrink-0')
        plain 'sign-up ready — click to open'
      end
      div(class: 'flex items-center gap-2') do
        span(class: 'w-4 h-4 rounded border border-dashed border-accent/45 shrink-0')
        plain 'rides, no sign-up yet — click to make one'
      end
    end
  end

  def anchor(date) = "d-#{date.strftime('%Y-%m-%d')}"

  # --- what is coming up ----------------------------------------------------

  def upcoming
    div(class: 'flex flex-col gap-2.5') { @dates.each { |day| date_card(day) } }
  end

  def date_card(day)
    div(id: anchor(day.date),
        class: 'flex flex-col rounded-lg border border-line bg-surface overflow-hidden scroll-mt-4') do
      div(class: 'flex items-baseline gap-2 px-3.5 pt-3 pb-1') do
        span(class: 'font-display font-bold text-[15px]') { day.date.strftime('%A %-d %B') }
        span(class: 'board-meta') { relative_label(day.date) }
      end

      div(class: 'flex flex-col') { day.events.each { |event| event_row(event) } }
      signup_row(day)
    end
  end

  def event_row(event)
    div(class: 'flex items-center gap-1 pr-2 hover:bg-surface-sunk') do
      a(href: path("/board?event_id=#{event.id}"),
        class: "flex flex-1 min-w-0 items-center gap-3 px-3.5 py-2 no-underline text-ink #{event.disabled ? 'opacity-55' : ''}") do
        span(class: 'font-mono text-[11.5px] text-ink/70 w-[68px] shrink-0') do
          event.start_time&.strftime('%-l:%M %p').to_s
        end
        span(class: "flex-1 min-w-0 text-[13px] font-medium #{event.disabled ? 'line-through' : ''}") { event.name.to_s }
        render Components::EventBadge.new(event: event) if event.disabled
        span(class: 'board-meta whitespace-nowrap') { roster(event) }
      end
      cancel_button(event) if @leader
    end
  end

  # Cancelling switches the occurrence OFF; it does not delete the row.
  #
  # Two reasons, and the first is not sentiment. The series regenerates its
  # dates every day, so a deleted occurrence reappears within 24 hours — a
  # tombstone is required either way, and `disabled` already is one:
  # `ensure_occurrence` finds the row and leaves it alone. The second is that a
  # past occurrence is the only record of who rode with whom.
  #
  # For a whole holiday use an academic break instead; this is for the one-off
  # "no gathering this Friday".
  def cancel_button(event)
    confirm = if event.disabled
                nil
              else
                "Cancel #{event.name} on #{event.start_time&.strftime('%-d %b')}? " \
                'It stays on the schedule as cancelled, and nobody is dispatched for it.'
              end

    form(method: 'post', action: path("/events/#{event.id}/disable"), class: 'contents') do
      input(type: 'hidden', name: 'return_to', value: '/schedule')
      button(
        type: 'submit',
        data_confirm: confirm,
        title: event.disabled ? 'put this date back on' : 'cancel just this date',
        class: 'border-0 bg-transparent cursor-pointer text-[11px] font-medium px-1.5 py-1 rounded ' \
               "#{event.disabled ? 'text-accent hover:bg-accent-tint' : 'text-ink/45 hover:text-danger'}"
      ) { event.disabled ? 'Restore' : 'Cancel' }
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
      post ? a(href: path("/signups/#{post.id}"), class: 'board-btn no-underline text-ink') { 'Open' }
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

    form(method: 'post', action: path('/signups'), class: 'contents') do
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
        span(class: 'text-[11.5px] text-ink/60 px-1') do
          'These keep generating on their own — nothing to press. Use the breaks ' \
          'below to stop them over a holiday, or cancel a single date above.'
        end
        breaks_section
      end
    end
  end

  def series_row(s)
    a(href: path("/series/#{s.id}"),
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

      form(method: 'post', action: path("/breaks/#{academic_break.id}"), class: 'contents') do
        input(type: 'hidden', name: '_method', value: 'delete')
        button(type: 'submit', title: 'Remove',
               class: 'border-0 bg-transparent text-ink/55 hover:text-danger font-mono text-xs font-semibold cursor-pointer px-1') do
          '✕'
        end
      end
    end
  end

  def add_break_form
    form(method: 'post', action: path('/breaks'), class: 'flex gap-2 items-end flex-wrap pt-1') do
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
