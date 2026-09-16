require_relative 'components/master'

# Create or edit a one-off event — a retreat, a special service. Recurring
# occurrences are generated from a series and are edited there.
class EventForm < Phlex::HTML
  include Components

  def initialize(event:, channels:, locations:, leader: false, error: nil)
    @event = event
    @channels = channels
    @locations = locations
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: title, leader: @leader) do
      div(class: 'max-w-xl flex flex-col gap-5 font-sans text-ink') do
        h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { title }
        error_note if @error
        generated_note if @event.recurring?
        form_body
      end
    end
  end

  private

  def title
    @event.new_record? ? 'New event' : "Edit #{@event.name}"
  end

  def action
    @event.new_record? ? '/events' : "/events/#{@event.id}"
  end

  def error_note
    p(role: 'alert', class: 'text-sm text-danger') { @error }
  end

  def generated_note
    div(class: 'p-3 rounded-lg border border-line bg-surface-sunk text-[12.5px] text-ink/70') do
      plain 'This occurrence was generated from a series. Editing it here changes '
      plain 'only this week — change the series to affect future weeks.'
    end
  end

  def form_body
    form(method: 'post', action: action, class: 'flex flex-col gap-4') do
      input(type: 'hidden', name: '_method', value: 'patch') unless @event.new_record?

      field('Name') { text_field('name', @event.name) }
      field('Section') { section_select }

      div(class: 'grid grid-cols-2 gap-3') do
        field('Starts') { datetime_field('start_time', @event.start_time) }
        field('Ends') { datetime_field('end_time', @event.end_time) }
      end

      div(class: 'grid grid-cols-2 gap-3') do
        field('Channel') { belongs_to_select('channel_id', @channels, @event.channel_id) }
        field('Location') { belongs_to_select('location_id', @locations, @event.location_id) }
      end

      label(class: 'flex items-center gap-2 text-[13px]') do
        input(type: 'hidden', name: 'disabled', value: '0')
        input(type: 'checkbox', name: 'disabled', value: '1', checked: @event.disabled, class: 'accent-accent')
        plain 'Disabled'
      end

      div(class: 'flex gap-2 pt-1') do
        button(type: 'submit', class: 'board-btn-solid') { @event.new_record? ? 'Create event' : 'Save changes' }
        a(href: cancel_href, class: 'board-btn no-underline') { 'Cancel' }
      end
    end
  end

  def cancel_href
    @event.new_record? ? '/events' : "/events/#{@event.id}"
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

  # datetime-local wants "YYYY-MM-DDTHH:MM" in local time.
  def datetime_field(name, value)
    input(
      type: 'datetime-local',
      name: name,
      value: value&.strftime('%Y-%m-%dT%H:%M').to_s,
      class: 'board-input'
    )
  end

  def section_select
    select(name: 'section', class: 'board-input') do
      option(value: '', selected: @event.section.blank?) { '—' }
      Event::SECTIONS.each do |section|
        option(value: section, selected: @event.section == section) { section }
      end
    end
  end

  def belongs_to_select(name, records, selected)
    select(name: name, class: 'board-input') do
      option(value: '', selected: selected.nil?) { '—' }
      records.each do |record|
        option(value: record.id, selected: selected == record.id) { record.name.to_s }
      end
    end
  end

end
