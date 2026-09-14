require_relative 'hfile'
require_relative 'bot'

class Bot
  class Scheduler
    def initialize(bot, messenger = nil)
      @scheduler = Rufus::Scheduler.new(discard_past: false)
      @bot = bot
      # Was never assigned, so every collect job died on `@messenger.dm_ian`.
      @messenger = messenger
      schedule_existing_events
      @task_thread = Thread.new { task_scheduler } #simplest way to ensure all events are scheduled
      at_exit do
        Event.scheduled.map(&:unschedule) #scheduler lives in memory only
        @task_thread.join
      end
    end

    # @param event [Event]
    # @return scheduled event [Event]
    def schedule(event)
      ssi = schedule_rides_message event
      csi = schedule_rides_collect event
      event.update(scheduled: true, send_schedule_id: ssi, collect_schedule_id: csi)
      puts "scheduled #{event}"
    end

    private
    def collect_scheduled_message(event)
      event = Event.find(event.id)
      return unless event && event.enabled? && event.rides_message_id

      reaction_users = @bot.channel(event.channel.discord_id).load_message(event.rides_message_id).all_reaction_users

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

      @messenger&.dm_ian "reaction details for event: #{event}\n#{summary}"
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

    def schedule_existing_events
      Event.upcoming.unscheduled.each do |event|
        next unless event.schedulable?

        #ensure the message actually exists in the server
        begin
          event.update(rides_message_id: nil) unless @bot.channel(event.channel.discord_id).load_message(event.rides_message_id)
        rescue ArgumentError
        end
        schedule event
      end
    end

    def schedule_rides_collect(event)
      case event.repeats_every
      when 'week'
        collect = "#{event.collect_rides_at.min} #{event.collect_rides_at.hour} * * #{event.collect_rides_at.wday}"

        @scheduler.schedule_cron collect do
          collect_scheduled_message event
        end
      else
        # `when 'never' || '' || nil` evaluated to just `when 'never'`, so a blank
        # or nil repeats_every scheduled nothing at all.
        @scheduler.schedule_at event.collect_rides_at do
          collect_scheduled_message event
        end
      end
    end

    def schedule_rides_message(event)
      case event.repeats_every
      when 'week'
        message = "#{event.message_rides_at.min} #{event.message_rides_at.hour} * * #{event.message_rides_at.wday}"

        @scheduler.schedule_cron message do
          send_scheduled_message event
        end
      else
        @scheduler.schedule_at event.message_rides_at do
          send_scheduled_message event
        end
      end
    end

    def send_scheduled_message(event)
      event = Event.find(event.id) #update the event upon calling
      if event && event.enabled? && !event.rides_message_id
        rides_message = @bot.send(event.channel.discord_id, event.message)
        event.emojis.each do |emoji|
          rides_message.react emoji
        end
        event.update({ rides_message_id: rides_message.id })
      end
    end

    def task_scheduler #proof of original sin
      @scheduler.every '5 minutes' do
        schedule_existing_events
      end
    end
  end
end
