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

  SECTIONS = %w[early late].freeze

  # Which of a person's two addresses to collect them from. Sunday morning
  # everyone is at home; Friday evening most people come straight from a lab.
  PICKUP_SOURCES = { 'home' => 'Home address', 'class' => 'Friday class location' }.freeze

  validates :pickup_source, inclusion: { in: PICKUP_SOURCES.keys }

  # Legacy Rufus-cron bookkeeping. The poller replaced it; the columns are
  # dropped a release later so a surviving old bot process does not crash in its
  # at_exit block. See db/migrate/2200.
  self.ignored_columns += %w[repeats_every scheduled send_schedule_id collect_schedule_id]

  scope :active, -> { where(disabled: false) }
  scope :inactive, -> { where(disabled: true) }

  # A ride is finished when its DAY is, not two hours after it starts.
  #
  # The old rule guessed an end two hours in whenever none was recorded, and
  # that guess decided whether the board still offered to dispatch. A 7am–5pm
  # retreat was therefore "over" at 9am — PAST pill up and Send to drivers gone,
  # on the morning of the retreat, while people were still being collected.
  #
  # Ending at midnight needs no end time at all, and is wrong in the harmless
  # direction: a board that stays open a few hours too long costs nothing, where
  # one that closes early costs a dispatch you cannot send.
  #
  # `end_time` is still honoured when it is there, so something genuinely
  # spanning two days stays live until the second one is over.
  scope :past, -> { where('coalesce(end_time, start_time) < ?', Time.zone.now.beginning_of_day) }
  # The complement, at the same day granularity — so an event earlier today is
  # in exactly one of these, not in neither.
  scope :upcoming, -> { where('coalesce(end_time, start_time) >= ?', Time.zone.now.beginning_of_day) }

  scope :recurring, -> { where.not(series_id: nil) }
  scope :one_off, -> { where(series_id: nil) }
  scope :section, ->(section) { where(section: section) }
  scope :chronological, -> { order(:start_time) }

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

  def recurring?
    series_id.present?
  end

  def one_off?
    series_id.nil?
  end

  # Has a sign-up post been sent for this occurrence?
  def posted?
    signup_posts.any?(&:posted?)
  end

  # Which driver tag this occurrence draws from.
  #
  # Inherited from the series rather than copied down at generation, so renaming
  # the tag on "Abide" applies to the occurrences that already exist — the
  # alternative silently left three weeks of already-generated Fridays pointing
  # at the old name. The column on events is an override for a one-off, where
  # nil means "whatever the series says".
  def driver_tag_for_board
    driver_tag.presence || series&.driver_tag.presence
  end

  # Mirrors `scope :past`, so Ruby and SQL agree on when a ride is over.
  def past?
    finish = end_time || start_time
    return false if finish.nil?

    finish.to_date < Time.zone.today
  end

  def to_h #this allows for the object to be passed directly into Discordrb methods
    { name: name, id: discord_id }
  end

  def to_s
    "#{name} at [#{location}] from #{start_time&.strftime('%Y-%m-%d %H:%M')} until #{end_time&.strftime('%Y-%m-%d %H:%M')}"
  end

  # "Friday Bible Study — early" etc.
  # "Abide — 6:30 PM".
  #
  # The qualifier used to be a `section` — early / late — which someone had to
  # choose and which told you less than the clock does. Two services on a
  # Sunday are told apart by the time you turn up, so that is what the name
  # says.
  #
  # Callers that already print a time use `name` instead, or it appears twice.
  def display_name
    return name.to_s if start_time.blank?

    "#{name} — #{start_time.strftime('%-l:%M %p')}"
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
