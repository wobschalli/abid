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

  # unpublished (0) replaces the old "draft" state. Database rows in this state
  # are intentionally saved but not scheduled. cancelled (4) keeps historical
  # records of events that were called off.
  enum :status, { unpublished: 0, scheduled: 1, active: 2, completed: 3, cancelled: 4 }

  scope :active, -> { where(status: [:scheduled, :active]) }
  scope :current, -> { where("start_time <= :now AND end_time >= :now", now: Time.current) }
  scope :inactive, -> { where(status: [:unpublished, :cancelled, :completed]) }
  scope :past, -> { where("end_time <= ?", Time.current) }
  scope :not_scheduled, -> { where(scheduled: false) }
  scope :scheduled_scope, -> { where(scheduled: true) }
  scope :upcoming, -> { where("start_time >= ?", Time.current) }
  scope :unscheduled, -> { where(scheduled: false) }
  scope :not_unpublished, -> { where.not(status: :unpublished) }
  scope :published, -> { where(status: [:scheduled, :active]) }

  validates :name, presence: true
  validates :start_time, :end_time, :message_rides_at, :collect_rides_at, presence: true, unless: :unpublished?
  validate :times_are_in_order, unless: :unpublished?

  def schedulable?
    name.present? && start_time && end_time && message_rides_at && collect_rides_at &&
      channel && location && message.present? && emojis.any?
  end

  def unpublished?
    status == 'unpublished'
  end

  def cancelled?
    status == 'cancelled'
  end

  def to_h #this allows for the object to be passed directly into Discordrb methods
    { name: name, id: discord_id }
  end

  def to_s
    "#{name} at [#{location}] from #{start_time&.strftime('%Y-%m-%d %H:%M')} until #{end_time&.strftime('%Y-%m-%d %H:%M')}"
  end

  def unschedule
    self.scheduled = false
    self.send_schedule_id = nil
    self.collect_schedule_id = nil
    self.save(validate: false)
  end

  private

  def times_are_in_order
    return unless [start_time, end_time, message_rides_at, collect_rides_at].all?

    errors.add(:message_rides_at, 'must be before the event starts') if message_rides_at >= start_time
    errors.add(:collect_rides_at, 'must be between the message time and the event end') if collect_rides_at < message_rides_at || collect_rides_at > end_time
    errors.add(:end_time, 'must be after the start time') if end_time <= start_time
  end
end
