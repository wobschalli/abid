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
        # Queued beats everything: a row is sitting in the outbox and the bot
        # will take it on the next tick. Without this a message waiting to go
        # looked exactly like one never sent, so pressing send appeared to do
        # nothing for up to thirty seconds.
        if queued_ride_ids.include?(ride.id) then :queued
        elsif prior.nil? then :never
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
    @board.driver_rides.select { |r| r.active? && !%i[sent queued].include?(states[r.id]) }
  end

  def queued_count
    states.values.count(:queued)
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

  # Drivers with a message already in the outbox, waiting for the bot.
  def queued_ride_ids
    @queued_ride_ids ||= DispatchMessage
                         .joins(:dispatch)
                         .where(dispatches: { event_id: @board.event.id })
                         .where(status: 'pending')
                         .pluck(:driver_ride_id).compact.to_set
  end

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
