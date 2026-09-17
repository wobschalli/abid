class DispatchMessage < ApplicationRecord
  # What one driver was told, and whether it arrived.
  #
  # driver_name, discord_id, body and roster are denormalised because the ride
  # rows they describe get deleted — `Event has_many :rides, dependent:
  # :destroy`, and the board has a Remove button. The log has to survive that.
  STATUSES = %w[pending sent failed skipped].freeze

  belongs_to :dispatch
  belongs_to :driver_ride, class_name: 'Ride', optional: true
  belongs_to :user, optional: true

  has_one :event, through: :dispatch

  validates :status, inclusion: { in: STATUSES }
  validates :discord_id, :driver_name, :roster_digest, presence: true

  scope :pending, -> { where(status: 'pending') }
  scope :sent, -> { where(status: 'sent') }
  scope :acknowledged, -> { where.not(acknowledged_at: nil) }
  scope :unacknowledged, -> { sent.where(acknowledged_at: nil) }
  scope :failed, -> { where(status: 'failed') }

  # The driver pressed "Got it" on their DM. Only meaningful once sent — an
  # unsent message cannot have been acknowledged.
  def acknowledged? = acknowledged_at.present?

  def acknowledge!
    return false if acknowledged? || !sent?

    update!(acknowledged_at: Time.zone.now)
  end

  def sent?
    status == 'sent'
  end

  def failed?
    status == 'failed'
  end

  def riders
    roster['riders'] || []
  end

  def rider_names
    riders.map { |r| r['name'] }
  end

  # Populated at send time, so a failed DM can be read and passed on by hand.
  def phone
    user&.phone
  end
end
