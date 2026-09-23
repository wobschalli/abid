require_relative 'components/master'

class SeriesShow < Phlex::HTML
  include Components

  DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  def initialize(series:, upcoming:, past:, leader: false)
    @series = series
    @upcoming = upcoming
    @past = past
    @leader = leader
  end

  def view_template
    Layout(title: @series.display_name, leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        breadcrumb
        header
        facts
        section('Upcoming occurrences', @upcoming, 'None generated yet.')
        section('Past occurrences', @past, 'No history yet.')
      end
    end
  end

  private

  def breadcrumb
    div(class: 'text-[12px] text-ink/60') do
      a(href: path('/schedule'), class: 'text-accent no-underline hover:underline') { 'Schedule' }
      plain ' / '
      plain @series.name.to_s
    end
  end

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      div(class: 'flex items-baseline gap-2.5 flex-wrap') do
        h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { @series.name.to_s }
        render Components::EventBadge.new(series: @series)
      end
      div(class: 'flex-1')
      if @leader
        a(href: path("/series/#{@series.id}/edit"), class: 'board-btn-solid no-underline') { 'Edit' }
      end
    end
  end

  def facts
    div(class: 'grid gap-3 grid-cols-[repeat(auto-fit,minmax(160px,1fr))]') do
      fact('Day', @series.weekday ? DAYS[@series.weekday] : '—')
      fact('Time', @series.start_time_of_day&.strftime('%-l:%M %p') || '—')
      fact('Location', @series.location&.name || '—')
      fact('Channel', @series.channel&.name || '—')
      fact('Generates ahead', "#{@series.horizon_weeks} weeks")
      fact('First week', @series.starts_on&.strftime('%-d %b %Y') || 'no limit')
      fact('Last week', @series.ends_on&.strftime('%-d %b %Y') || 'open ended')
      fact('Last generated', @series.last_generated_on&.strftime('%-d %b %Y') || 'never')
    end
  end

  def fact(label, value)
    div(class: 'flex flex-col gap-1 p-3 rounded-lg border border-line bg-surface-sunk') do
      span(class: 'board-label') { label }
      span(class: 'text-[13px]') { value.to_s }
    end
  end

  def section(title, events, empty)
    div(class: 'flex flex-col gap-2') do
      span(class: 'board-label') { title }
      render Components::EventTable.new(events: events, empty: empty)
    end
  end
end
