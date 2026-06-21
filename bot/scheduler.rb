require_relative 'hfile'
require_relative 'bot'

class Bot
  class Scheduler
    def initialize(bot, messenger)
      @scheduler = Rufus::Scheduler.new(discard_past: false)
      @bot = bot
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
      if event && event.rides_message_id
        reaction_users = @bot.channel(event.channel.discord_id)
                             .load_message(event.rides_message_id)
                             .all_reaction_users

        driver_emoji = event.emojis[0]
        rider_emoji = event.emojis[1]

        # Prioritize drivers
        drivers = []
        if driver_emoji
          d_users = reaction_users[driver_emoji.to_reaction] || reaction_users[driver_emoji.modal_display] || []
          db_users = d_users.map { |u| User.find_by(discord_id: u.id) unless u.bot_account }.compact.uniq
          db_users.each do |u|
            EventSignup.find_or_create_by!(event: event, user: u, emoji: driver_emoji) do |es|
              es.response_type = :driver
            end
            drivers << u
          end
        end

        riders = []
        if rider_emoji
          r_users = reaction_users[rider_emoji.to_reaction] || reaction_users[rider_emoji.modal_display] || []
          db_users = r_users.map { |u| User.find_by(discord_id: u.id) unless u.bot_account }.compact.uniq
          db_users.each do |u|
            next if drivers.include?(u)
            EventSignup.find_or_create_by!(event: event, user: u, emoji: rider_emoji) do |es|
              es.response_type = :rider
            end
            riders << u
          end
        end

        message = "reaction details for event: #{event}\n"
        message += "Drivers: #{drivers.map(&:name).join(', ')}\n"
        message += "Riders: #{riders.map(&:name).join(', ')}\n"

        if riders.any? && drivers.any?
          @matcher = Bot::Matcher.new(@bot)
          assignments = @matcher.match_riders_to_drivers(event, riders, drivers)

          summary = assignments.map { |assignment|
            "#{assignment[:driver].name}: #{assignment[:riders].map(&:name).join(', ')}"
          }.join("\n")
          message += "\nRide Assignments:\n#{summary}"
        end

        @messenger.dm_mods message
        event.save
      end
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
      when 'never' || '' || nil
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
      when 'never' || '' || nil
        @scheduler.schedule_at event.message_rides_at do
          send_scheduled_message event
        end
      end
    end

    def send_scheduled_message(event)
      event = Event.find(event.id) #update the event upon calling
      if event && !event.draft? && !event.cancelled? && !event.rides_message_id
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
