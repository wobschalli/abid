require_relative 'hfile'
require_relative 'bot'

class Bot
  # Drives everything time-based in the bot from a single poll.
  #
  # This replaced a Rufus cron-per-event design that was the direct cause of the
  # "a weekly event posts exactly once, ever" bug: one Event row was reused for
  # every week, `send_scheduled_message` bailed as soon as `rides_message_id` was
  # set, and nothing ever cleared it. With one Event row per occurrence,
  # "already posted" is a per-occurrence fact, and the two scopes below — which
  # were written months ago and never called — become the whole engine.
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
      Event.message_due.find_each { |event| safely(event) { post_rides_message(event) } }
      Event.collection_due.find_each { |event| safely(event) { collect_reactions(event) } }
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

    # Materialise upcoming occurrences once a day rather than every 30 seconds.
    def generate_occurrences
      return if @generated_on == Time.zone.today

      EventGenerator.call
      @generated_on = Time.zone.today
    rescue StandardError => e
      warn "occurrence generation failed: #{e.class}: #{e.message}"
    end

    def post_rides_message(event)
      message = @bot.send(event.channel.discord_id, event.message)

      # Record the id *before* reacting. events.rides_message_id is UNIQUE, and a
      # reaction failing partway through must not leave the occurrence looking
      # unposted — that would repost the whole message on the next tick.
      event.update_column(:rides_message_id, message.id)

      event.emojis.each { |emoji| message.react(emoji) }
    end

    def collect_reactions(event)
      event = Event.find(event.id)
      return unless event&.enabled? && event.rides_message_id

      reaction_users = @bot.channel(event.channel.discord_id)
                           .load_message(event.rides_message_id)
                           .all_reaction_users

      # `event.users = ...` used to run inside this loop, so each emoji replaced
      # the previous one's reactors and only the last emoji survived.
      signed_up = []
      summary = reaction_users.map do |emoji, users|
        signed_up.concat(known_users(users))
        "#{emoji}: #{users.join(', ')}"
      end.join("\n")

      signed_up.uniq!
      event.users = signed_up
      event.collected_at = Time.zone.now
      event.save

      sync_rides(event, signed_up)

      @messenger&.dm_leaders "reaction details for event: #{event}\n#{summary}"
    end

    def known_users(reaction_users)
      reaction_users.filter_map do |reaction_user|
        next if reaction_user.bot_account?

        User.find_by(discord_id: reaction_user.id)
      end
    end

    # Turn sign-ups into Ride rows so the web ride board has something to show.
    # Everyone comes in as a rider; coordinators flip people to driver on the
    # board, since the reaction emoji doesn't say which one someone meant.
    def sync_rides(event, users)
      users.each do |user|
        ride = event.rides.find_or_initialize_by(user_id: user.id)
        next if ride.persisted?

        ride.role = 'rider'
        ride.status = 'requested'
        ride.zone = user.location&.zone
        ride.signed_up_at = Time.zone.now
        ride.save
      end
    rescue StandardError => e
      warn "could not sync rides for event #{event.id}: #{e.class}: #{e.message}"
    end

    # One bad occurrence must not stop the tick from servicing the others.
    def safely(event)
      yield
    rescue StandardError => e
      warn "event #{event.id}: #{e.class}: #{e.message}"
    end
  end
end
