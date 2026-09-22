require_relative 'components/master'

# The seeded pickup areas. The list itself is real geography maintained in
# db/locations.rb, but the ADDRESS is editable here, because it is the one piece
# a human has to supply: geocoding searches OpenStreetMap, which knows streets
# and not leasing brands, so "Third and West" resolves to nothing while the
# street it stands on resolves fine.
class LocationsIndex < Phlex::HTML
  include Components

  def initialize(by_zone:, unzoned:, usage:, leader: false)
    @by_zone = by_zone
    @unzoned = unzoned
    @usage = usage
    @leader = leader
  end

  def view_template
    Layout(title: 'Locations', leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        header
        note
        add_form if @leader
        Location::ZONES.each { |zone| zone_section(zone, @by_zone[zone] || []) }
        zone_section('Unzoned', @unzoned) if @unzoned.any?
      end
    end
  end

  private

  def header
    div(class: 'flex items-baseline gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Locations' }
      span(class: 'board-meta') { "#{@by_zone.values.sum(&:size) + @unzoned.size} places" }
    end
  end

  def note
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[12.5px] leading-[1.6] text-ink/75') do
      plain 'Pickup areas around Purdue. The board groups the waiting queue by zone, and '
      plain 'Optimize routes between these places by real driving time — so an address here '
      plain 'is not decoration, it is what decides who rides with whom. '
      plain 'The shared list lives in '
      code(class: 'font-mono text-[11.5px]') { 'db/locations.rb' }
      plain ', and you can add your own below. Anything marked '
      strong { 'no coords' }
      plain ' could not be found on the map by name — apartment brands are not map '
      plain 'features, but the streets they stand on are. Give it a street address '
      plain 'and it is looked up when you save.'
    end
  end

  # The seed file is still the source of truth for the places everyone shares;
  # this is for the ones it does not know about yet.
  def add_form
    form(method: 'post', action: '/locations',
         class: 'flex flex-wrap gap-2 items-end p-3.5 rounded-lg border border-line bg-surface') do
      label(class: 'flex flex-col gap-1 flex-1 min-w-[150px]') do
        span(class: 'board-label') { 'New place' }
        input(type: 'text', name: 'name', required: true, placeholder: 'e.g. Rise on Chauncey',
              class: 'board-input text-[12.5px] py-1.5')
      end
      label(class: 'flex flex-col gap-1') do
        span(class: 'board-label') { 'Zone' }
        select(name: 'zone', class: 'board-input text-[12.5px] py-1.5 w-auto') do
          Location::ZONES.each { |z| option(value: z) { z } }
        end
      end
      label(class: 'flex flex-col gap-1 flex-1 min-w-[150px]') do
        span(class: 'board-label') { 'Street address' }
        input(type: 'text', name: 'address', placeholder: 'looked up on save',
              class: 'board-input text-[12.5px] py-1.5')
      end
      button(type: 'submit', class: 'board-btn-solid') { 'Add' }
    end
  end

  def zone_section(zone, locations)
    return if locations.empty?

    div(class: 'flex flex-col gap-2') do
      div(class: 'flex items-baseline gap-2') do
        span(class: 'board-label') { zone }
        span(class: 'font-mono text-[10px] text-ink/60') { locations.size.to_s }
      end
      div(class: 'flex flex-col gap-1.5') { locations.each { |l| row(l) } }
    end
  end

  def row(location)
    div(class: 'flex items-start gap-3 px-3 py-2.5 rounded-lg border border-line bg-surface') do
      div(class: 'flex-1 min-w-0 flex flex-col gap-0.5') do
        div(class: 'flex items-baseline gap-2 flex-wrap') do
          span(class: 'font-semibold text-[13px]') { location.name.to_s }
          verification_pill(location)
        end
        if location.aliases.present?
          span(class: 'board-meta') { "also: #{location.aliases.join(', ')}" }
        end
        address_form(location)
      end
      div(class: 'flex items-center gap-2 shrink-0') do
        span(class: 'font-mono text-[11px] text-ink/70 whitespace-nowrap') { usage_label(location) }
        verify_button(location) if @leader
        delete_button(location) if @leader
      end
    end
  end

  # How sure we are the pin is the building. "no coords" used to be the only
  # signal, which made an eyeballed guess and a rooftop match look identical —
  # and drivers were sent to both with equal confidence.
  def verification_pill(location)
    style, label, hint =
      case location.verification
      when 'rooftop' then ['bg-accent-tint text-accent', 'verified', 'matched to the building']
      when 'interpolated' then ['bg-accent-tint text-accent', 'verified', 'matched to the street number']
      when 'approximate' then ['bg-warn-tint text-warn-ink', 'approximate', 'somewhere near here — worth checking the address']
      else
        location.coords? ? ['bg-ink/[.07] text-ink/60', 'unverified', 'a hand-placed pin, never checked'] :
                           ['bg-warn-tint text-warn-ink', 'no coords', 'not on the map at all']
      end

    span(title: hint,
         class: "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase #{style}") do
      label
    end
  end

  # Offered for anything short of verified. One press asks Google (then OSM)
  # and writes back the state — the way to re-pin a place after fixing its
  # address, without a rake task.
  def verify_button(location)
    return if location.verified?

    form(method: 'post', action: "/locations/#{location.id}/verify", class: 'contents') do
      button(type: 'submit', title: 'Look this place up and record how well it matched',
             class: 'board-btn whitespace-nowrap text-[11.5px] py-1') { 'Verify' }
    end
  end

  # Offered only for a place nothing points at. Deleting one that is in use
  # would blank somebody's home address with no way to recover what it was, so
  # the button is simply absent rather than present-and-failing.
  def delete_button(location)
    return if in_use?(location)

    form(method: 'post', action: "/locations/#{location.id}", class: 'contents') do
      input(type: 'hidden', name: '_method', value: 'delete')
      button(
        type: 'submit',
        data_confirm: "Delete #{location.name}? Nothing points at it.",
        title: 'delete this place',
        class: 'border-0 bg-transparent cursor-pointer text-ink/35 hover:text-danger text-[13px] font-mono px-1'
      ) { '✕' }
    end
  end

  def in_use?(location)
    (@usage[location.id] || {}).values.sum.positive?
  end

  # Saving looks the address up straight away, so the feedback loop is one
  # press rather than "edit a seed file and re-run a rake task".
  def address_form(location)
    unless @leader
      span(class: 'board-meta') { location.address } if location.address.present?
      return
    end

    form(method: 'post', action: "/locations/#{location.id}",
         class: 'flex gap-2 items-center pt-1') do
      input(type: 'hidden', name: '_method', value: 'patch')
      input(type: 'text', name: 'address', value: location.address.to_s,
            placeholder: location.coords? ? 'street address (optional)' : 'street address — needed to place this on the map',
            class: 'board-input text-[12px] py-1.5')
      button(type: 'submit', class: 'board-btn whitespace-nowrap') { 'Save' }
    end
  end

  def usage_label(location)
    counts = @usage[location.id] || {}
    parts = []
    parts << "#{counts[:users]} live here" if counts[:users].to_i.positive?
    parts << "#{counts[:classes]} class here" if counts[:classes].to_i.positive?
    parts << "#{counts[:rides]} pickups" if counts[:rides].to_i.positive?
    parts << "#{counts[:events]} events" if counts[:events].to_i.positive?
    parts.empty? ? 'unused' : parts.join(' · ')
  end
end
