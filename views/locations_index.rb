require_relative 'components/master'

# Reference view of the seeded pickup areas. Read-only on purpose: the list is
# real geography maintained in db/locations.rb, not something to edit per-event.
# It exists so you can check which zone a complex landed in without opening a
# console, and so the sidebar link is not a 404.
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
      plain 'Edit the list in '
      code(class: 'font-mono text-[11.5px]') { 'db/locations.rb' }
      plain ' and re-run '
      code(class: 'font-mono text-[11.5px]') { 'rake db:seed' }
      plain '. Coordinates are approximate — '
      code(class: 'font-mono text-[11.5px]') { 'rake db:geocode' }
      plain ' refines them.'
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
      end
      span(class: 'font-mono text-[11px] text-ink/70 whitespace-nowrap') { usage_label(location) }
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
