class User < ApplicationRecord
  # Home / default pickup point. Optional because members are auto-created from
  # Discord joins long before anyone tells us where they live.
  belongs_to :location, optional: true

  # NOTE: dependent: :destroy here is why Messenger#handle_member_leave must
  # never destroy a User — it would take every historical ride with it.
  has_many :rides, dependent: :destroy
  has_and_belongs_to_many :events
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
  # Somebody the coordinator cannot fully plan around yet.
  scope :missing_details, -> { where(location_id: nil).or(where(phone: [nil, ''])) }
  scope :search, lambda { |query|
    key = "%#{query.to_s.strip.downcase}%"
    where('lower(coalesce(name, \'\')) LIKE :k OR lower(coalesce(username, \'\')) LIKE :k', k: key)
  }

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

  def to_s
    display_name
  end
end
