class Event < ApplicationRecord
  belongs_to :channel, optional: true
  belongs_to :location, optional: true
  belongs_to :series, class_name: 'EventSeries', optional: true

  has_many :emojis
  has_many :rides, dependent: :destroy
  has_many :participants, through: :rides, source: :user

  # `belongs_to :driver` pointed at an events.driver_id column that does not
  # exist, and `has_many :riders, foreign_key: 'driver_id'` resolved against
  # users.driver_id — a user→user link that meant something else entirely.
  # Driving is per-occurrence, so it lives on Ride now.
  has_many :driver_rides, -> { drivers }, class_name: 'Ride'
  has_many :drivers, through: :driver_rides, source: :user

  # Kept for the existing reaction-collection path; new code should use rides.
  has_and_belongs_to_many :users

  SECTIONS = %w[early late].freeze

  scope :active, -> { where(disabled: false) }
  scope :current, -> { where("start_time <= :now AND end_time >= :now", now: Time.zone.now) }
  scope :inactive, -> { where(disabled: true) }
  scope :past, -> { where("end_time <= ?", Time.zone.now) }
  scope :not_scheduled, -> { where(scheduled: false) }
  scope :scheduled, -> { where(scheduled: true) }
  scope :upcoming, -> { where("start_time >= ?", Time.zone.now) }
  scope :unscheduled, -> { where(scheduled: false) }

  scope :section, ->(section) { where(section: section) }
  scope :chronological, -> { order(:start_time) }

  # Occurrences whose rides message is due but hasn't gone out yet. Recurrence is
  # one row per occurrence now, so "already posted" is a per-occurrence fact
  # rather than a flag that permanently latches the series off.
  scope :message_due, lambda {
    active.where(rides_message_id: nil)
          .where.not(message_rides_at: nil)
          .where('message_rides_at <= ?', Time.zone.now)
  }

  scope :collection_due, lambda {
    active.where(collected_at: nil)
          .where.not(rides_message_id: nil)
          .where.not(collect_rides_at: nil)
          .where('collect_rides_at <= ?', Time.zone.now)
  }

  def disable
    self.disabled = true
    self.save
  end

  def disabled?
    self.disabled
  end

  def enable
    self.disabled = false
    self.save
  end

  def enabled?
    !self.disabled
  end

  def schedulable?
    name && start_time && end_time && message_rides_at && collect_rides_at && channel && location
  end

  def to_h #this allows for the object to be passed directly into Discordrb methods
    { name: name, id: discord_id }
  end

  def to_s
    "#{name} at [#{location}] from #{start_time&.strftime('%Y-%m-%d %H:%M')} until #{end_time&.strftime('%Y-%m-%d %H:%M')}"
  end

  # "Friday Bible Study — early" etc.
  def display_name
    section.present? ? "#{name} — #{section}" : name.to_s
  end

  def riders
    rides.riders
  end

  def seats_offered
    driver_rides.sum(&:seats_available)
  end

  def seats_needed
    rides.riders.count
  end

  def unassigned_riders
    rides.riders.unassigned
  end

  def unschedule
    self.scheduled = false
    self.send_schedule_id = ''
    self.collect_schedule_id = ''
    self.save
  end
end
