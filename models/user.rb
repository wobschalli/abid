class User < ApplicationRecord
  # Home / default pickup point. Optional because members are auto-created from
  # Discord joins long before anyone tells us where they live.
  belongs_to :location, optional: true

  # NOTE: dependent: :destroy here is why Messenger#handle_member_leave must
  # never destroy a User — it would take every historical ride with it.
  has_many :rides, dependent: :destroy

  # Where they are before a Friday event — usually their last class, which is
  # rarely where they live. The census has people living at Lark and standing
  # outside MSEE when they need collecting.
  belongs_to :class_location, class_name: 'Location', optional: true
  # `has_and_belongs_to_many :events` lived here over the events_users join,
  # which the legacy rides-message path wrote and 2900 dropped. Rides are the
  # record of who was on an occurrence.
  has_and_belongs_to_many :roles

  has_secure_password

  # Capacity is how many passengers, so 4 means four people besides the driver.
  validates :capacity, numericality: { only_integer: true, greater_than_or_equal_to: 0,
                                       less_than_or_equal_to: 20 },
                       allow_nil: true
  # Wide enough to cover anyone still at Purdue plus a few years either side; a
  # typo like 202 or 20267 is what this is really for.
  validates :grad_year, numericality: { only_integer: true, greater_than: 1950,
                                        less_than: 2100 },
                        allow_nil: true

  scope :leaders, -> { where(leader: true) }
  # Who is actually part of the fellowship this year, as opposed to everyone who
  # has ever joined the Discord. Set by the census import and by the toggle on
  # the members page.
  scope :active, -> { where(active: true) }
  scope :other, -> { where(active: false) }
  scope :drivers, -> { where.not(capacity: nil).where('capacity > 0') }
  # The exact complement of `drivers`: everyone who needs a seat rather than
  # offering one. This is the roster a rides coordinator actually works from.
  scope :riders, -> { where(capacity: nil).or(where(capacity: ..0)) }
  scope :by_name, -> { order(Arel.sql('lower(coalesce(name, username))')) }
  # Everyone carrying a tag. `@>` is the array-contains operator, which the GIN
  # index on tags serves directly.
  scope :tagged, ->(tag) { where('tags @> ARRAY[?]::varchar[]', tag.to_s) }
  # Somebody the coordinator cannot fully plan around yet.
  scope :missing_details, -> { where(location_id: nil).or(where(phone: [nil, ''])) }
  scope :search, lambda { |query|
    key = "%#{query.to_s.strip.downcase}%"
    where('lower(coalesce(name, \'\')) LIKE :k OR lower(coalesce(username, \'\')) LIKE :k', k: key)
  }

  before_validation :tidy_tags

  # What a tag looks like once it is stored: trimmed, spaces to hyphens, and
  # matched case-insensitively against tags that already exist.
  #
  # The last part is the one that matters. Without it "friday-usual" typed on a
  # Tuesday is a different tag from "Friday-Usual", the board quietly finds
  # nobody, and the only clue is a count of zero. Canonicalising to the existing
  # spelling means the first person to use a tag names it and everyone after
  # them joins it, however they type it.
  def self.canonical_tag(value)
    tag = value.to_s.strip.gsub(/\s+/, '-')
    return nil if tag.empty?

    known.find { |existing| existing.casecmp?(tag) } || tag
  end

  # Every tag the app knows about: the ones people already carry, plus the ones
  # the schedule asks for.
  #
  # The second half matters on day one. Tags only existed on users, so before
  # anybody was tagged the list was empty — no chips, nothing to click, and no
  # way to apply the first tag from the members list. "Friday-Usual" is a real
  # tag the moment a series asks for it, whether or not a person has it yet.
  def self.known_tags
    registered = DriverTag.pluck(:name)
    from_users = connection.select_values('SELECT DISTINCT unnest(tags) FROM users')
    from_series = EventSeries.where.not(driver_tag: [nil, '']).distinct.pluck(:driver_tag)

    (registered + from_users + from_series).uniq { |t| t.downcase }.sort
  end

  def self.known
    known_tags
  end
  private_class_method :known

  def display_name
    name.presence || username.presence || "user #{discord_id}"
  end

  def can_drive?
    capacity.to_i.positive?
  end

  # The ride this user has for a given event, if any.
  def ride_for(event)
    rides.find_by(event_id: event.id)
  end

  def zone
    location&.zone
  end

  # "Class of 2027". grad_year sat unused in the schema from the very first
  # migration until this page.
  def class_of
    grad_year.present? ? "Class of #{grad_year}" : nil
  end

  def missing_details
    missing = []
    missing << 'home area' if location_id.nil?
    missing << 'phone' if phone.blank?
    missing
  end

  def missing_details?
    missing_details.any?
  end

  def tagged?(tag)
    tags.any? { |t| t.casecmp?(tag.to_s) }
  end

  def to_s
    display_name
  end

  private

  # Blank entries come from an empty box in the tag form; duplicates come from
  # adding a tag somebody already has. Neither is an error worth showing anyone.
  def tidy_tags
    return if tags.nil?

    self.tags = tags.filter_map { |t| self.class.canonical_tag(t) }.uniq(&:downcase)
  end
end
