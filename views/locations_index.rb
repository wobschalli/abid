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
      plain 'Pickup areas around Purdue. The board groups the waiting queue by zone, '
      plain 'auto-fill prefers a driver in the same zone, and a driver collects one zone at a time. '
      plain 'The list itself lives in '
      code(class: 'font-mono text-[11.5px]') { 'db/locations.rb' }
      plain '. Anything marked '
      strong { 'no coords' }
      plain ' could not be found on the map by name — apartment brands are not map '
      plain 'features, but the streets they stand on are. Give it a street address '
      plain 'and it is looked up when you save.'
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
          unless location.coords?
            span(class: 'font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] bg-warn-tint text-warn-ink uppercase') do
              'no coords'
            end
          end
        end
        if location.aliases.present?
          span(class: 'board-meta') { "also: #{location.aliases.join(', ')}" }
        end
        address_form(location)
      end
      span(class: 'font-mono text-[11px] text-ink/70 whitespace-nowrap') { usage_label(location) }
    end
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
    parts << "#{counts[:rides]} pickups" if counts[:rides].to_i.positive?
    parts.empty? ? '—' : parts.join(' · ')
  end
end
