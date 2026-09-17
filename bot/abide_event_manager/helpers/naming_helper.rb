module NamingHelper

  private

  # ---------------------------------------------------------------------------
  # Naming helpers
  # ---------------------------------------------------------------------------

  def generate_unique_event_name(base_name)
    base = base_name.strip
    existing = Event.where("name LIKE ?", "#{base}%").pluck(:name)
    return base if existing.none?

    numbers = existing.map { |n| n.match(/\((\d+)\)$/)&.[](1).to_i }
    next_number = (numbers.max || 0) + 1
    "#{base} (#{next_number})"
  end

  def generate_duplicate_name(base_name)
    clean_name = base_name.to_s.sub(/\s*\(\d+\)$/, '').strip
    existing = Event.where("name LIKE ?", "#{clean_name}%").pluck(:name)
    return clean_name if existing.none?

    numbers = existing.map { |n| n.match(/\((\d+)\)$/)&.[](1).to_i }
    next_number = (numbers.max || 0) + 1
    "#{clean_name} (#{next_number})"
  end
end
