require_relative 'hfile'
require_relative 'bot'

class Bot
  # Drives everything time-based in the bot from a single poll.
  #
  # There used to be a second posting path here — Event.message_due ->
  # post_rides_message -> collect_reactions — running alongside the sign-up
  # publisher and posting `events.message` off its own schedule. It is gone:
  # two mechanisms announcing the same rides could both land in the channel,
  # and it had been raising NoMethodError on `event.emojis` after committing
  # the message id ever since that association was dropped.
  #
  # Polling also means no in-memory schedule to lose, so a restart costs nothing
  # and a bot that was down catches up on its own.
  class Scheduler
    TICK = '30s'.freeze
    RECONCILE_TICK = '5m'.freeze

    def initialize(bot, messenger = nil)
      @bot = bot
      @messenger = messenger
      @scheduler = Rufus::Scheduler.new

      # overlap: false — a slow tick must not stack up behind itself and post
      # the same message twice.
      @scheduler.every TICK, overlap: false do
        with_connection { tick }
      end

      # Sign-up sweeps are cheap (one request per post unless a count moved) but
      # not free, so they run less often than the main tick. An on-demand sweep
      # from the dashboard is picked up within 15 seconds.
      @scheduler.every '15s', overlap: false do
        with_connection { reconcile(SignupPost.reconcile_requested) }
        # Same cadence: both are "the dashboard asked for something", and a
        # coordinator who has just realised the post is wrong is watching the
        # channel while they wait.
        with_connection { revoke_requested }
      end

      @scheduler.every RECONCILE_TICK, overlap: false do
        with_connection { reconcile(SignupPost.tracking) }
      end

      # The real answer to dropped gateway events: everything that happened
      # while the bot was down or resuming gets picked up the moment it starts.
      Thread.new { with_connection { reconcile(SignupPost.tracking) } }

      # Bounded. `shutdown(:wait)` waits for running jobs *forever*, so a tick
      # wedged on a slow Discord call held the process open until SIGKILL. Every
      # job here is an idempotent sweep that redoes itself on the next boot, so
      # ten seconds then letting go loses nothing.
      at_exit { @scheduler.shutdown(wait: 10) }
    end

    private

    # Rufus runs every job in its own thread. Without this each tick checks out
    # an ActiveRecord connection and never returns it, and the pool (5) is
    # exhausted within minutes.
    def with_connection(&block)
      ActiveRecord::Base.connection_pool.with_connection(&block)
    end

    def tick
      generate_occurrences
      publish_signups
      send_dispatches
      seat_late_riders
    end

    # Someone reacted after the drivers were dispatched. Seat them into the
    # cheapest feasible car — the optimizer pins everyone already seated, so
    # the only change is one addition, and exactly that one driver flips to
    # "changed" for a one-person re-send.
    #
    # A sweep rather than a per-reaction hook: reaction bursts collapse into
    # one solve, it is idempotent, and it catches up after a bot restart.
    # Before the first dispatch the board belongs to the coordinator, so
    # pre-dispatch reactions keep landing in the queue untouched.
    def seat_late_riders
      Event.active.upcoming.where(start_time: Time.zone.now..).find_each do |event|
        board = RideBoard.new(event)
        next if board.pool.none? { |ride| ride.from_discord? }
        next unless board.dispatch_status.anything_sent?

        result = Rides::Optimizer.call(board)
        if result.seated.positive?
          warn "late sweep seated #{result.seated} on #{event.display_name} (#{result.engine})"
        end
      end
    rescue StandardError => e
      warn "late-rider sweep failed: #{e.class}: #{e.message}"
    end

    # Drains the dispatch outbox. If the bot was down when a coordinator pressed
    # send, the row waited and goes out now.
    def send_dispatches
      DispatchSender.new(@bot, @messenger).pump
    rescue StandardError => e
      warn "dispatch pump failed: #{e.class}: #{e.message}"
    end

    # Sends any sign-up post whose scheduled time has arrived. Worst-case
    # latency is one tick, which is fine for "post this on Thursday evening".
    def publish_signups
      Signup::Publisher.new(@bot).run_once
    rescue StandardError => e
      warn "signup publish failed: #{e.class}: #{e.message}"
    end

    def reconcile(scope)
      Signup::Reconciler.new(@bot).run_all(scope)
    rescue StandardError => e
      warn "signup reconcile failed: #{e.class}: #{e.message}"
    end

    def revoke_requested
      Signup::Revoker.new(@bot).run_all
    rescue StandardError => e
      warn "signup revoke failed: #{e.class}: #{e.message}"
    end

    # Materialise upcoming occurrences once a day rather than every 30 seconds,
    # then give each new ride date its sign-up post. Generation first: the
    # scheduler can only cover dates that exist.
    def generate_occurrences
      return if @generated_on == Time.zone.today

      EventGenerator.call
      created = Signup::AutoSchedule.new.call
      warn "auto-scheduled #{created.size} sign-up post(s)" if created.any?
      @generated_on = Time.zone.today
    rescue StandardError => e
      warn "occurrence generation failed: #{e.class}: #{e.message}"
    end





  end
end
