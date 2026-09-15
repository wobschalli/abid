class Event < ApplicationRecord
  belongs_to :channel, optional: true
  belongs_to :location, optional: true
  belongs_to :series, class_name: 'EventSeries', optional: true

  # `has_many :emojis` lived here over a single emojis.event_id column, so
  # binding an emoji to one event stole it from another. Sign-up emoji are
  # SignupOption rows now, and one emoji can mean a different ride every week.
  has_many :signup_options
  has_many :signup_posts, through: :signup_options

  has_many :rides, dependent: :destroy
  # restrict_with_error, not destroy: once drivers have been told who they are
  # collecting, that record outlives the board.
  has_many :dispatches, dependent: :restrict_with_error
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

  # How late the bot may still post a rides message it missed. Beyond this the
  # occurrence is skipped rather than posted — a bot that has been down for a
  # week should not wake up and dump ten stale sign-up posts into the channel.
  POST_GRACE = 6.hours

  # Legacy Rufus-cron bookkeeping. The poller replaced it; the columns are
  # dropped a release later so a surviving old bot process does not crash in its
  # at_exit block. See db/migrate/2200.
  self.ignored_columns += %w[repeats_every scheduled send_schedule_id collect_schedule_id]

  scope :active, -> { where(disabled: false) }
  scope :current, -> { where("start_time <= :now AND end_time >= :now", now: Time.zone.now) }
  scope :inactive, -> { where(disabled: true) }
  # Events created through the Discord modal often have no end_time, and would
  # never appear under Past without the fallback.
  scope :past, -> { where("coalesce(end_time, start_time + interval '2 hours') <= ?", Time.zone.now) }
  scope :upcoming, -> { where("start_time >= ?", Time.zone.now) }

  scope :recurring, -> { where.not(series_id: nil) }
  scope :one_off, -> { where(series_id: nil) }
  scope :section, ->(section) { where(section: section) }
  scope :chronological, -> { order(:start_time) }

  # Occurrences whose rides message is due but hasn't gone out yet. Recurrence is
  # one row per occurrence now, so "already posted" is a per-occurrence fact
  # rather than a flag that permanently latches the series off.
  scope :message_due, lambda {
    active.where(rides_message_id: nil)
          .where.not(message_rides_at: nil)
          .where.not(channel_id: nil)
          .where.not(message: nil)
          .where(message_rides_at: POST_GRACE.ago..Time.zone.now)
          .where('start_time > ?', Time.zone.now)
          # A coordinator has already written a sign-up post covering this
          # occurrence; posting our own would split the roster across two
          # messages.
          .where.not(id: SignupOption.published.select(:event_id))
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

  # Has everything the bot needs to post a rides message for this occurrence.
  # Replaces `schedulable?`, which asked whether a Rufus job could be registered.
  def postable?
    name.present? && start_time && message_rides_at && channel_id && message.present?
  end

  def recurring?
    series_id.present?
  end

  def one_off?
    series_id.nil?
  end

  def posted?
    rides_message_id.present?
  end

  # Mirrors the coalesce in `scope :past`, so Ruby and SQL agree on when an
  # occurrence is over. Events created through the Discord modal often have no
  # end_time.
  def end_time_or_estimate
    end_time || (start_time && start_time + 2.hours) || Time.zone.now
  end

  def past?
    end_time_or_estimate <= Time.zone.now
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

end
