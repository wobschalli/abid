# How often someone has driven recently.
#
# This is what keeping every past occurrence is actually *for*. Left to memory,
# the same two or three people end up driving every week and nobody notices
# until they burn out and stop coming.
#
# "Of the last N occurrences" rather than "in the last N weeks" on purpose: a
# series that skipped a fortnight for spring break should not make someone look
# like they have gone quiet.
class DriverLoad
  DEFAULT_WINDOW = 8

  def initialize(window: DEFAULT_WINDOW)
    @window = window
  end

  # The most recent finished occurrences, newest first.
  def recent_events
    @recent_events ||= Event.active.past.order(start_time: :desc).limit(@window).to_a
  end

  def window_size
    recent_events.size
  end

  # { user_id => count of those occurrences they drove }
  def drove_counts
    @drove_counts ||= counts_for('driver')
  end

  # { user_id => count of those occurrences they rode in }
  def rode_counts
    @rode_counts ||= counts_for('rider')
  end

  def drove(user)
    drove_counts.fetch(user.id, 0)
  end

  def rode(user)
    rode_counts.fetch(user.id, 0)
  end

  # "drove 5 of the last 8" — nil when there is nothing worth saying.
  #
  # Only speaks about people who drive. "drove 0 of the last 8" on someone who
  # has never owned a car is noise; on someone with seats who has not been
  # asked in two months, it is the useful half of the picture.
  def summary(user)
    return nil if window_size.zero?
    return nil unless drove(user).positive? || user.can_drive?

    "drove #{drove(user)} of the last #{window_size}"
  end

  # Drivers carrying an unusual share of the load. Deliberately a ratio, not a
  # raw count: three of the last four is a heavier ask than five of the last
  # twenty.
  def heavy_load?(user, threshold: 0.6)
    return false if window_size < 3

    drove(user).to_f / window_size >= threshold
  end

  private

  def counts_for(role)
    return {} if recent_events.empty?

    Ride.active
        .where(event_id: recent_events.map(&:id), role: role)
        .group(:user_id)
        .count
  end
end
