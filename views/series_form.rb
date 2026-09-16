require_relative 'components/master'

class SeriesForm < Phlex::HTML
  include Components

  DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  def initialize(series:, channels:, locations:, leader: false, error: nil)
    @series = series
    @channels = channels
    @locations = locations
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: title, leader: @leader) do
      div(class: 'max-w-xl flex flex-col gap-5 font-sans text-ink') do
        h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { title }
        p(role: 'alert', class: 'text-sm text-danger') { @error } if @error
        form_body
      end
    end
  end

  private

  def title
    @series.new_record? ? 'New series' : "Edit #{@series.name}"
  end

  def action
    @series.new_record? ? '/series' : "/series/#{@series.id}"
  end

  def form_body
    form(method: 'post', action: action, class: 'flex flex-col gap-4') do
      input(type: 'hidden', name: '_method', value: 'patch') unless @series.new_record?

      field('Name') { text_field('name', @series.name) }
      field('Section') { section_select }

      div(class: 'grid grid-cols-2 gap-3') do
        field('Day') { weekday_select }
        field('Repeats') { interval_select }
      end

      div(class: 'grid grid-cols-2 gap-3') do
        field('Starts at') { time_field('start_time_of_day', @series.start_time_of_day) }
        field('Ends at') { time_field('end_time_of_day', @series.end_time_of_day) }
      end

      div(class: 'grid grid-cols-2 gap-3') do
        field('Send sign-up (days ahead)') { number_field('signup_lead_days', @series.signup_lead_days, min: 0, max: 30) }
        field('At what time') { time_field('signup_post_time', @series.signup_post_time) }
      end

      div(class: 'grid grid-cols-2 gap-3') do
        field('Channel') { belongs_to_select('channel_id', @channels, @series.channel_id) }
        field('Location') { belongs_to_select('location_id', @locations, @series.location_id) }
      end

      div(class: 'grid grid-cols-3 gap-3') do
        field('First week') { date_field('starts_on', @series.starts_on) }
        field('Last week') { date_field('ends_on', @series.ends_on) }
        field('Generate ahead (weeks)') { number_field('horizon_weeks', @series.horizon_weeks, min: 1, max: 26) }
      end

      # The line that used to be retyped on every single post, or forgotten.
      field('Collect people from') do
        select(name: 'pickup_source', class: 'board-input') do
          Event::PICKUP_SOURCES.each do |value, label|
            option(value: value, selected: @series.pickup_source == value) { label }
          end
        end
        span(class: 'text-[11.5px] text-ink/60') do
          'Friday events usually collect from the last class; Sunday from home.'
        end
      end

      field('Sign-up footer (optional)') { outro_field }

      label(class: 'flex items-center gap-2 text-[13px]') do
        input(type: 'hidden', name: 'disabled', value: '0')
        input(type: 'checkbox', name: 'disabled', value: '1', checked: @series.disabled, class: 'accent-accent')
        plain 'Disabled — stops generating new occurrences, keeps past ones'
      end

      div(class: 'flex gap-2 pt-1') do
        button(type: 'submit', class: 'board-btn-solid') { @series.new_record? ? 'Create series' : 'Save changes' }
        a(href: @series.new_record? ? '/schedule' : "/series/#{@series.id}", class: 'board-btn no-underline') { 'Cancel' }
      end
    end
  end

  def field(label, &block)
    div(class: 'flex flex-col gap-[5px]') do
      span(class: 'board-label') { label }
      yield
    end
  end

  def text_field(name, value)
    input(type: 'text', name: name, value: value.to_s, class: 'board-input')
  end

  def time_field(name, value)
    input(type: 'time', name: name, value: value&.strftime('%H:%M').to_s, class: 'board-input')
  end

  def date_field(name, value)
    input(type: 'date', name: name, value: value&.strftime('%Y-%m-%d').to_s, class: 'board-input')
  end

  def number_field(name, value, min:, max:)
    input(type: 'number', name: name, value: value.to_s, min: min, max: max, class: 'board-input font-mono')
  end

  def weekday_select
    select(name: 'weekday', class: 'board-input') do
      option(value: '', selected: @series.weekday.nil?) { '—' }
      DAYS.each_with_index do |day, index|
        option(value: index, selected: @series.weekday == index) { day }
      end
    end
  end

  def interval_select
    select(name: 'interval_weeks', class: 'board-input') do
      { 1 => 'Every week', 2 => 'Every 2 weeks', 3 => 'Every 3 weeks', 4 => 'Every 4 weeks' }.each do |weeks, label|
        option(value: weeks, selected: @series.interval_weeks == weeks) { label }
      end
    end
  end

  def section_select
    select(name: 'section', class: 'board-input') do
      option(value: '', selected: @series.section.blank?) { '—' }
      Event::SECTIONS.each do |section|
        option(value: section, selected: @series.section == section) { section }
      end
    end
  end

  def belongs_to_select(name, records, selected)
    select(name: name, class: 'board-input') do
      option(value: '', selected: selected.nil?) { '—' }
      records.each { |r| option(value: r.id, selected: selected == r.id) { r.name.to_s } }
    end
  end

  def outro_field
    textarea(
      name: 'signup_outro',
      rows: 2,
      class: 'board-input resize-y text-[12.5px] leading-[1.5]',
      placeholder: 'e.g. React by 8am Sunday'
    ) { @series.signup_outro.to_s }
  end
end
