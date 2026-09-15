# Per-driver dispatch state for one occurrence: never sent, sent, changed since
# sent, or the DM failed.
#
# One query for the whole board, so the card badges cost nothing extra.
class DispatchStatus
  STATES = %i[never sent changed failed].freeze

  def initialize(board)
    @board = board
  end

  # { driver_ride_id => :never | :sent | :changed | :failed }
  def states
    @states ||= @board.driver_rides.to_h do |ride|
      prior = last_messages[ride.id]
      state =
        if prior.nil? then :never
        elsif prior.status == 'failed' then :failed
        elsif prior.roster_digest != digest_for(ride) then :changed
        else :sent
        end
      [ride.id, state]
    end
  end

  def state_for(driver_ride)
    states[driver_ride.id] || :never
  end

  # Drivers who need a message: never sent, changed since, or last attempt
  # failed.
  def stale_driver_rides
    @board.driver_rides.select { |r| r.active? && states[r.id] != :sent }
  end

  def anything_sent?
    last_messages.any?
  end

  def last_sent_at
    last_messages.values.filter_map(&:sent_at).max
  end

  def failed_count
    states.values.count(:failed)
  end

  def changed_count
    states.values.count(:changed)
  end

  private

  def last_messages
    @last_messages ||= DispatchMessage
                       .joins(:dispatch)
                       .where(dispatches: { event_id: @board.event.id })
                       .where(status: %w[sent failed])
                       .order(:created_at)
                       .index_by(&:driver_ride_id) # later rows win
  end

  # Moving one rider changes both the old and the new driver's digest, so both
  # correctly show as needing a re-send. No extra bookkeeping needed.
  def digest_for(driver_ride)
    car = @board.cars.find { |c| c.id == driver_ride.id }
    riders = car ? car.passengers : []
    DispatchDigest.for(driver_ride, riders, @board.event)
  end
end
