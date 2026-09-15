require_relative 'components/master'

class EventsIndex < Phlex::HTML
  include Components

  TABS = [
    ['upcoming', 'Upcoming'],
    ['past', 'Past'],
    ['all', 'All']
  ].freeze

  def initialize(events:, filter: 'upcoming', leader: false)
    @events = events
    @filter = filter
    @leader = leader
  end

  def view_template
    Layout(title: 'Events', leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        header
        tabs
        if @filter == 'past'
          grouped_by_month
        else
          render Components::EventTable.new(events: @events, empty: empty_message)
        end
      end
    end
  end

  private

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Events' }
      div(class: 'flex-1')
      a(href: '/series', class: 'board-btn no-underline') { 'Recurring series' }
      a(href: '/events/new', class: 'board-btn-solid no-underline') { 'New event' } if @leader
    end
  end

  def tabs
    div(class: 'flex gap-1 p-[3px] bg-ink/5 rounded-lg self-start') do
      TABS.each do |value, label|
        current = @filter == value
        a(
          href: "/events?when=#{value}",
          class: [
            'cursor-pointer font-semibold text-[11.5px] px-[11px] py-1.5 rounded-md no-underline',
            current ? 'bg-surface text-ink shadow-[0_1px_2px_rgba(23,32,28,.12)]' : 'bg-transparent text-ink/70 hover:text-ink'
          ].join(' ')
        ) { label }
      end
    end
  end

  # Past events run to hundreds of rows over a year; month headings make it
  # scannable without paging.
  def grouped_by_month
    if @events.empty?
      return div(class: 'px-1 py-6 text-[13px] text-ink/65') { empty_message }
    end

    @events.group_by { |e| e.start_time&.beginning_of_month }.each do |month, events|
      div(class: 'flex flex-col gap-2') do
        span(class: 'board-label') { month ? month.strftime('%B %Y') : 'Undated' }
        render Components::EventTable.new(events: events)
      end
    end
  end

  def empty_message
    case @filter
    when 'past' then 'No past events yet.'
    when 'all' then 'No events yet. Create one here, or with /event create in Discord.'
    else 'Nothing coming up. Recurring series generate their occurrences automatically.'
    end
  end
end
