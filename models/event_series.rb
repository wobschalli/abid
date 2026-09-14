class EventSeries < ApplicationRecord
  # The recurring template — "Friday Bible Study, early section, weekly".
  # Concrete Event rows are generated ahead of time from this, so each week has
  # its own rides message, its own roster, and its own history.
  belongs_to :channel, optional: true
  belongs_to :location, optional: true

  has_many :events, foreign_key: :series_id, dependent: :nullify

  validates :name, presence: true
  validates :weekday, inclusion: { in: 0..6 }, allow_nil: true
  validates :section, inclusion: { in: Event::SECTIONS }, allow_blank: true

  scope :active, -> { where(disabled: false) }

  def display_name
    section.present? ? "#{name} — #{section}" : name.to_s
  end

  # Build (without saving) the occurrence for the week containing `date`.
  def occurrence_for(date)
    return nil if weekday.nil? || start_time_of_day.nil?

    day = date.to_date
    day += (weekday - day.wday) % 7 if day.wday != weekday
    starts = combine(day, start_time_of_day)

    events.build(
      name: name,
      section: section,
      channel: channel,
      location: location,
      message: message,
      start_time: starts,
      end_time: end_time_of_day ? combine(day, end_time_of_day) : nil,
      message_rides_at: starts - (message_lead_hours || 24).hours,
      collect_rides_at: starts - (collect_lead_hours || 2).hours,
      disabled: disabled
    )
  end

  # Idempotent: generating twice for the same week reuses the existing row rather
  # than posting a second rides message.
  def ensure_occurrence(date)
    candidate = occurrence_for(date)
    return nil if candidate.nil?

    existing = events.find_by(start_time: candidate.start_time)
    return existing if existing

    candidate.save
    candidate
  end

  def generate_upcoming(weeks: 2, from: Time.zone.today)
    (0...weeks).filter_map { |offset| ensure_occurrence(from + (offset * 7)) }
  end

  private

  def combine(day, time_of_day)
    Time.zone.local(day.year, day.month, day.day, time_of_day.hour, time_of_day.min)
  end
end
