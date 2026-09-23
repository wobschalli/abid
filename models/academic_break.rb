class AcademicBreak < ApplicationRecord
  # A stretch of the university calendar when nobody is around — winter break,
  # spring break, summer. Recurring series skip these, so the bot does not post
  # sign-up messages into an empty server every week of December.
  #
  # Shared by every series on purpose: the calendar belongs to Purdue, not to
  # one Bible study.
  validates :name, presence: true
  validates :starts_on, :ends_on, presence: true
  validate :ends_on_after_starts_on

  scope :chronological, -> { order(:starts_on) }
  scope :upcoming, -> { where('ends_on >= ?', Time.zone.today).chronological }
  scope :covering, ->(date) { where('starts_on <= :d AND ends_on >= :d', d: date) }

  # One query, then an in-memory check — occurrence generation asks this for
  # every candidate date across every series.
  def self.ranges(from: nil, to: nil)
    scope = all
    scope = scope.where('ends_on >= ?', from) if from
    scope = scope.where('starts_on <= ?', to) if to
    scope.chronological.map { |b| b.starts_on..b.ends_on }
  end

  def self.covers?(date, ranges: nil)
    (ranges || ranges()).any? { |range| range.cover?(date) }
  end

  def covers?(date)
    (starts_on..ends_on).cover?(date)
  end

  # Occurrences generated before this break existed are now wrong. Disable
  # rather than destroy — a destroy takes the roster with it, and only
  # still-upcoming ones are touched so history is never rewritten.
  #
  # @return [Integer] how many were switched off
  def disable_future_occurrences!
    Event.active
         .recurring
         .where(occurrence_date: starts_on..ends_on)
         .where('start_time > ?', Time.zone.now)
         .update_all(disabled: true, updated_at: Time.zone.now)
  end

  def days
    (ends_on - starts_on).to_i + 1
  end

  def range_label
    if starts_on.year == ends_on.year
      "#{starts_on.strftime('%-d %b')} – #{ends_on.strftime('%-d %b %Y')}"
    else
      "#{starts_on.strftime('%-d %b %Y')} – #{ends_on.strftime('%-d %b %Y')}"
    end
  end

  def past?
    ends_on < Time.zone.today
  end

  private

  def ends_on_after_starts_on
    return if starts_on.blank? || ends_on.blank?
    return if ends_on >= starts_on

    errors.add(:ends_on, 'is before the start date')
  end
end
