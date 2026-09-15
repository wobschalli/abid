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
  validates :interval_weeks, numericality: { greater_than: 0 }
  validates :horizon_weeks, numericality: { greater_than: 0 }
  validate :time_zone_must_be_known

  scope :active, -> { where(disabled: false) }
  scope :generatable, -> { active.where.not(weekday: nil).where.not(start_time_of_day: nil) }

  def display_name
    section.present? ? "#{name} — #{section}" : name.to_s
  end

  def zone
    ActiveSupport::TimeZone[time_zone.to_s] || Time.zone
  end

  def recurring?
    weekday.present? && start_time_of_day.present?
  end

  # Every occurrence date in [from, to] on this series' cadence.
  #
  # Date arithmetic only. `time + 7.days` is 167 or 169 hours across a DST
  # boundary, which walks the whole schedule an hour off for eight months.
  def occurrence_dates(from: Time.zone.today, to: nil)
    return [] unless recurring?

    to ||= from + horizon_weeks.weeks
    to = [to, ends_on].compact.min

    day = first_occurrence_on_or_after([from, starts_on].compact.max)
    return [] if day.nil?

    dates = []
    while day <= to
      dates << day
      day += interval_weeks.weeks
    end
    dates
  end

  # Build (without saving) the occurrence for a specific calendar date.
  def occurrence_for(date)
    return nil unless recurring?

    day = date.to_date
    starts = combine(day, start_time_of_day)

    events.build(
      name: name,
      section: section,
      channel: channel,
      location: location,
      message: message,
      occurrence_date: day,
      start_time: starts,
      end_time: end_time_of_day ? combine(day, end_time_of_day) : nil,
      message_rides_at: starts - (message_lead_hours || 24).hours,
      collect_rides_at: starts - (collect_lead_hours || 2).hours,
      disabled: disabled
    )
  end

  # Idempotent: generating twice for the same date reuses the existing row rather
  # than posting a second rides message. The unique index is the arbiter, not the
  # read — the web "Generate now" button can race the bot's tick.
  def ensure_occurrence(date)
    day = date.to_date
    existing = events.find_by(occurrence_date: day)
    return existing if existing

    occurrence_for(day)&.tap(&:save!)
  rescue ActiveRecord::RecordNotUnique
    events.find_by(occurrence_date: day)
  end

  def generate_upcoming(from: Time.zone.today, weeks: nil)
    weeks ||= horizon_weeks
    created = occurrence_dates(from: from, to: from + weeks.weeks)
              .filter_map { |date| ensure_occurrence(date) }

    if created.any?
      update_column(:last_generated_on, created.filter_map(&:occurrence_date).max)
    end

    created
  end

  private

  # The first date on or after `floor` that falls on this series' weekday and
  # lands on the interval_weeks cadence measured from starts_on.
  def first_occurrence_on_or_after(floor)
    floor = floor.to_date
    anchor = (starts_on || floor).to_date
    day = anchor + ((weekday - anchor.wday) % 7)
    day += interval_weeks.weeks while day < floor
    return nil if ends_on && day > ends_on

    day
  end

  def combine(day, time_of_day)
    zone.local(day.year, day.month, day.day, time_of_day.hour, time_of_day.min)
  end

  def time_zone_must_be_known
    return if time_zone.blank?
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "#{time_zone.inspect} is not a known timezone")
  end
end
