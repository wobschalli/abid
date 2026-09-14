# Undo for the ride board.
#
# The design keeps a stack of whole-assignment snapshots in component state. The
# session here is a cookie with about 4KB to play with, so this records the
# minimum needed to reverse a step instead: which rides moved and where they
# were. An auto-fill that seats twenty people is still one undo step.
class AssignmentHistory
  LIMIT = 10

  def initialize(session, event)
    @session = session
    @event = event
  end

  def any?
    stack.any?
  end

  # Record where these rides are *now*, before they're changed.
  def record(rides)
    entry = Array(rides).map { |r| [r.id, r.driver_ride_id, r.status] }
    return if entry.empty?

    push(entry)
  end

  def undo!
    entry = stack.pop
    store(stack)
    return 0 if entry.blank?

    restored = 0
    Ride.transaction do
      entry.each do |ride_id, driver_ride_id, status|
        ride = @event.rides.find_by(id: ride_id)
        next if ride.nil?

        ride.update!(driver_ride_id: driver_ride_id, status: status)
        restored += 1
      end
    end
    restored
  end

  def clear!
    store([])
  end

  private

  def key
    "undo_#{@event.id}"
  end

  def stack
    @stack ||= Array(@session[key])
  end

  def push(entry)
    @stack = (stack + [entry]).last(LIMIT)
    store(@stack)
  end

  def store(value)
    @session[key] = value
  end
end
