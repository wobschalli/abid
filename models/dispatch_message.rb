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
  scope :failed, -> { where(status: 'failed') }

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
