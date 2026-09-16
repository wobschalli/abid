require_relative 'components/master'

# Landing page. Was a placeholder reading "you've successfully logged in";
# now it answers the question someone actually opens the dashboard with —
# what is next, and does it need attention.
class Home < Phlex::HTML
  include Components

  def initialize(next_event: nil, board: nil, upcoming: [], needs_setup: [], leader: false)
    @next_event = next_event
    @board = board
    @upcoming = upcoming
    @needs_setup = needs_setup
    @leader = leader
  end

  def view_template
    Layout(title: 'Abid', leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { greeting }
        @next_event ? next_up : nothing_upcoming
        attention if @needs_setup.any?
        later if @upcoming.any?
      end
    end
  end

  private

  def greeting
    hour = Time.zone.now.hour
    return 'Good morning' if hour < 12
    return 'Good afternoon' if hour < 18

    'Good evening'
  end

  def next_up
    div(class: 'flex flex-col gap-3 p-4 rounded-xl border border-line bg-surface') do
      div(class: 'flex items-baseline gap-2.5 flex-wrap') do
        span(class: 'board-label') { 'Next up' }
        span(class: 'board-meta') { @next_event.start_time&.strftime('%A %-d %b, %-l:%M %p').to_s }
      end

      div(class: 'flex items-center gap-3 flex-wrap') do
        span(class: 'font-display font-bold text-xl -tracking-[.015em]') { @next_event.name.to_s }
        div(class: 'flex-1')
        a(href: "/board?event_id=#{@next_event.id}", class: 'board-btn-solid no-underline') { 'Open ride board' }
      end

      stats if @board
    end
  end

  def stats
    div(class: 'flex gap-5 flex-wrap font-mono text-[11.5px] text-ink/70 pt-1 border-t border-line') do
      stat(@board.seated_count, 'seated')
      stat(@board.pool_count, 'waiting')
      stat(@board.cars.size, 'cars')
      stat(@board.seats_left, 'seats open')
    end

    return if @board.warnings.empty?

    div(class: 'flex items-start gap-2 text-[12.5px] text-warn-ink') do
      span(class: 'w-1.5 h-1.5 mt-1.5 rounded-full bg-warn flex-none')
      plain @board.warning_text
    end
  end

  def stat(value, label)
    span(class: 'pt-2') do
      span(class: 'text-ink font-semibold') { value.to_s }
      whitespace
      plain label
    end
  end

  def nothing_upcoming
    div(class: 'flex flex-col gap-2 p-4 rounded-xl border border-line bg-surface') do
      span(class: 'text-[13px] text-ink/70') { 'Nothing coming up.' }
      span(class: 'text-[12.5px] text-ink/60') do
        'Recurring series generate their occurrences automatically — check that one is set up.'
      end
      a(href: '/schedule', class: 'board-btn no-underline self-start') { 'Schedule' }
    end
  end

  # The data gap that quietly breaks zone grouping and dispatch.
  def attention
    div(class: 'flex flex-col gap-2 p-4 rounded-xl border border-warn/40 bg-warn-tint') do
      span(class: 'board-label !text-warn-ink') { 'Needs details' }
      span(class: 'text-[12.5px] text-warn-ink') do
        "#{@needs_setup.size} #{'person'.pluralize(@needs_setup.size)} have no home area or phone number. " \
        'Drivers cannot collect someone whose address nobody knows.'
      end
      a(href: '/users?filter=missing', class: 'board-btn no-underline self-start') { 'Fill them in' }
    end
  end

  def later
    div(class: 'flex flex-col gap-2') do
      span(class: 'board-label') { 'Coming up' }
      render Components::EventTable.new(events: @upcoming)
    end
  end
end
