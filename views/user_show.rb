require_relative 'components/master'

# One member: the details a coordinator needs to plan around them, and what
# they have actually been doing.
#
# Home area, car capacity and phone are edited here. Until this page existed
# none of the three was settable anywhere in the app — phone only through the
# ride board's details rail, and only for someone who already had a ride.
class UserShow < Phlex::HTML
  include Components

  def initialize(user:, locations:, load:, history:, leader: false, error: nil)
    @user = user
    @locations = locations
    @load = load
    @history = history
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: @user.display_name, leader: @leader) do
      div(class: 'max-w-3xl flex flex-col gap-5 font-sans text-ink') do
        breadcrumb
        header
        p(role: 'alert', class: 'text-sm text-danger') { @error } if @error

        div(class: 'grid gap-5 md:grid-cols-[1fr_260px] items-start') do
          details_form
          sidebar
        end

        recent_rides
      end
    end
  end

  private

  def breadcrumb
    div(class: 'text-[12px] text-ink/60') do
      a(href: '/users', class: 'text-accent no-underline hover:underline') { 'Members' }
      plain ' / '
      plain @user.display_name
    end
  end

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-xl -tracking-[.015em] capitalize') { @user.display_name }
      if @user.leader
        span(class: 'font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase bg-accent-tint text-accent') do
          'leader'
        end
      end
      div(class: 'flex-1')
      span(class: 'board-meta') { "@#{@user.username}" } if @user.username.present?
    end
  end

  # --- form ----------------------------------------------------------------

  def details_form
    form(method: 'post', action: "/users/#{@user.id}", class: 'flex flex-col gap-4') do
      input(type: 'hidden', name: '_method', value: 'patch')

      field('Name') { text_field('name', @user.name) }
      field('Phone') { text_field('phone', @user.phone, mono: true, placeholder: '(765) 555-0100') }

      field('Home area') do
        location_select('location_id', @user.location_id)
        span(class: 'text-[11.5px] text-ink/60') do
          'Where they live. Used by any event that collects from home, and sets their zone on the board.'
        end
      end

      field('Friday class location') do
        location_select('class_location_id', @user.class_location_id)
        span(class: 'text-[11.5px] text-ink/60') do
          'Where they are before a Friday event — usually their last class, rarely where they live. ' \
          'Used only by events set to collect from class; falls back to home when blank.'
        end
      end

      div(class: 'grid grid-cols-2 gap-3') do
        field('Car seats') do
          number_field('capacity', @user.capacity, min: 0, max: 20)
          span(class: 'text-[11.5px] text-ink/60') { 'Passengers, not counting them. Blank if they do not drive.' }
        end
        field('Graduating') { number_field('grad_year', @user.grad_year, min: 1951, max: 2099) }
      end

      if @leader
        label(class: 'flex items-center gap-2 text-[13px]') do
          input(type: 'hidden', name: 'active', value: '0')
          input(type: 'checkbox', name: 'active', value: '1', checked: @user.active?, class: 'accent-accent')
          plain 'Active this year — part of the fellowship, not just in the server'
        end

        label(class: 'flex items-center gap-2 text-[13px]') do
          input(type: 'hidden', name: 'leader', value: '0')
          input(type: 'checkbox', name: 'leader', value: '1', checked: @user.leader, class: 'accent-accent')
          plain 'Leader — can edit the board and dispatch drivers'
        end

        div(class: 'flex gap-2 pt-1') do
          button(type: 'submit', class: 'board-btn-solid') { 'Save' }
          a(href: '/users', class: 'board-btn no-underline') { 'Back' }
        end
      end
    end
  end

  def field(label, &block)
    div(class: 'flex flex-col gap-[5px]') do
      span(class: 'board-label') { label }
      yield
    end
  end

  def text_field(name, value, mono: false, placeholder: nil)
    input(type: 'text', name: name, value: value.to_s, placeholder: placeholder,
          disabled: !@leader, class: "board-input #{mono ? 'font-mono' : ''}")
  end

  def number_field(name, value, min:, max:)
    input(type: 'number', name: name, value: value.to_s, min: min, max: max,
          disabled: !@leader, class: 'board-input font-mono')
  end

  # Grouped by zone so an 80-entry list stays navigable. Shared by both address
  # fields — they draw from the same set of places; only the question differs.
  def location_select(name, selected_id)
    select(name: name, disabled: !@leader, class: 'board-input') do
      option(value: '', selected: selected_id.nil?) { 'Not set' }
      @locations.group_by(&:zone).sort_by { |zone, _| Location::ZONES.index(zone) || 99 }.each do |zone, places|
        optgroup(label: zone || 'Unzoned') do
          places.each do |place|
            option(value: place.id, selected: selected_id == place.id) { place.name.to_s }
          end
        end
      end
    end
  end

  # --- sidebar -------------------------------------------------------------

  def sidebar
    div(class: 'flex flex-col gap-3') do
      load_card
      missing_card if @user.missing_details?
    end
  end

  def load_card
    div(class: 'flex flex-col gap-1.5 p-3 rounded-lg border border-line bg-surface-sunk') do
      span(class: 'board-label') { 'Recent load' }
      if @load.window_size.zero?
        span(class: 'text-[12.5px] text-ink/65') { 'No finished events yet.' }
      else
        span(class: 'text-[13px]') { "Drove #{@load.drove(@user)} of the last #{@load.window_size}" }
        span(class: 'text-[12.5px] text-ink/65') { "Rode in #{@load.rode(@user)}" }
        if @load.heavy_load?(@user)
          span(class: 'text-[12px] text-warn-ink') { 'Carrying more than their share — worth spreading around.' }
        end
      end
    end
  end

  def missing_card
    div(class: 'flex flex-col gap-1.5 p-3 rounded-lg border border-warn/40 bg-warn-tint') do
      span(class: 'board-label !text-warn-ink') { 'Missing' }
      span(class: 'text-[12.5px] text-warn-ink') do
        "No #{@user.missing_details.join(', no ')}. Dispatch needs both to be useful."
      end
    end
  end

  # --- history -------------------------------------------------------------

  def recent_rides
    div(class: 'flex flex-col gap-2') do
      span(class: 'board-label') { 'Recent rides' }
      if @history.empty?
        div(class: 'px-1 py-4 text-[13px] text-ink/65') { 'No rides on record yet.' }
      else
        div(class: 'flex flex-col gap-1.5') { @history.each { |ride| ride_row(ride) } }
      end
    end
  end

  def ride_row(ride)
    event = ride.event
    a(
      href: "/events/#{event.id}",
      class: 'flex items-center gap-3 px-3 py-2 rounded-lg border border-line bg-surface no-underline text-ink hover:border-accent'
    ) do
      span(class: 'w-28 flex-none font-mono text-[11px] text-ink/70') do
        event.start_time&.strftime('%a %-d %b').to_s
      end
      span(class: 'flex-1 min-w-0 text-[12.5px]') { event.name.to_s }
      span(class: "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase #{role_style(ride)}") do
        role_label(ride)
      end
    end
  end

  def role_style(ride)
    return 'bg-ink/[.07] text-ink/70' if ride.out?

    ride.driver? ? 'bg-accent-tint text-accent' : 'bg-ink/[.07] text-ink/70'
  end

  def role_label(ride)
    return ride.status.tr('_', ' ') if ride.out?

    ride.role
  end
end
