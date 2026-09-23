# Runs the ride optimizer for one event off the web request.
#
# OR-Tools takes a couple of seconds on this server's single core; inside a
# puma request that stalled every other page load for the duration. As a job
# the button returns at once and the board refreshes when the solve lands.
#
# Consistency: the optimizer's own writes and `destroy` (marking this job
# done) commit in one transaction, so a crash mid-solve leaves the board as it
# was and the job still queued for a retry — never half-seated riders with a
# finished job, nor a finished solve with a job that runs again. The advisory
# lock serialises two presses on the same event; the optimizer is idempotent,
# so the second one finds nothing new to do.
class OptimizeJob < Que::Job
  # A solve that fails three times is not going to succeed on the fourth; the
  # optimizer already falls back to greedy internally, so a failure here means
  # something structural (event deleted, database gone).
  self.maximum_retry_count = 3

  def run(event_id)
    event = Event.find_by(id: event_id)
    return destroy if event.nil?

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{event.id.to_i})")
      Rides::Optimizer.call(RideBoard.new(event))
      destroy
    end
  end

  LOCK_NAMESPACE = 4_243 # arbitrary; keeps these locks apart from any other advisory-lock user

  # Queued or running, not yet finished — what the board shows as "Optimizing…".
  def self.pending_for?(event)
    Que::ActiveRecord::Model
      .where(job_class: name, finished_at: nil, expired_at: nil)
      .where("args->>0 = ?", event.id.to_s)
      .exists?
  end
end
