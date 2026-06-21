class Event < ApplicationRecord
  belongs_to :channel
  belongs_to :location
  belongs_to :organizer, class_name: 'User'

  has_many :event_signups, dependent: :destroy
  has_many :riders, through: :event_signups, source: :user
  has_many :emojis, dependent: :destroy
  has_many :ride_assignments, dependent: :destroy

  has_many :driver_assignments,
           -> { where(role: :driver) },
           class_name: 'RideAssignment'
  has_many :drivers,
           through: :driver_assignments,
           source: :user

  enum :status, { draft: 0, scheduled: 1, active: 2, completed: 3, cancelled: 4 }

  scope :active, -> { where(disabled: false) }
  scope :current, -> { where("start_time <= :now AND end_time >= :now", now: DateTime.now) }
  scope :inactive, -> { where(disabled: true) }
  scope :past, -> { where("end_time <= ?", DateTime.now) }
  scope :not_scheduled, -> { where(scheduled: false) }
  scope :scheduled, -> { where(scheduled: true) }
  scope :upcoming, -> { where("start_time >= ?", DateTime.now)}
  scope :unscheduled, -> { where(scheduled: false) }

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

  def unschedule
    self.scheduled = false
    self.send_schedule_id = ''
    self.collect_schedule_id = ''
    self.save
  end
end
