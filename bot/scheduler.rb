require_relative 'hfile'
require_relative 'app_manager'

class AppManager
  class Scheduler
    def initialize(bot)
      @scheduler = Rufus::Scheduler.new(discard_past: false)
      @bot = bot
      rehydrate_schedules!
      @task_thread = Thread.new { task_scheduler }
      at_exit do
        Event.scheduled_scope.each(&:unschedule)
        @task_thread.join
      end
    end

    # @param event [Event]
    # @return scheduled event [Event]
    def schedule(event)
      unschedule(event) if event.scheduled?
      ssi = schedule_rides_message event
      csi = schedule_rides_collect event
      event.update!(scheduled: true, send_schedule_id: ssi, collect_schedule_id: csi)
      puts "scheduled #{event}"
    end

    # @param event [Event]
    def unschedule(event)
      return unless event.scheduled?

      @scheduler.job(event.send_schedule_id)&.unschedule if event.send_schedule_id
      @scheduler.job(event.collect_schedule_id)&.unschedule if event.collect_schedule_id
      event.unschedule
    end

    private

    def rehydrate_schedules!
      Event.where(status: :scheduled).find_each do |event|
        next unless event.schedulable?
        next if event.message_rides_at.nil? || event.collect_rides_at.nil?

        # If the collection time has already passed, the event is effectively over.
        next if event.collect_rides_at < Time.now

        # Ensure the previously sent rides message still exists; if not, clear it
        # so a new one can be sent on schedule.
        begin
          if event.rides_message_id && @bot.client.channel(event.channel.discord_id).load_message(event.rides_message_id).nil?
            event.update!(rides_message_id: nil)
          end
        rescue ArgumentError
          event.update!(rides_message_id: nil)
        end

        schedule(event)
      end
    end

    def collect_scheduled_message(event)
      event = Event.find(event.id)
      return unless event.rides_message_id

      message = @bot.client.channel(event.channel.discord_id).load_message(event.rides_message_id)
      return unless message

      driver_emoji = event.emojis[0]
      rider_emoji = event.emojis[1]

      drivers = []
      if driver_emoji
        d_users = message.reaction_users(driver_emoji.to_reaction) || []
        d_users.concat(message.reaction_users(driver_emoji.modal_display) || [])
        d_users.uniq.each do |u|
          next if u.bot_account
          user = User.find_by(discord_id: u.id)
          next unless user&.driver?
          EventSignup.find_or_create_by!(event: event, user: user, emoji: driver_emoji) do |es|
            es.response_type = :driver
          end
          drivers << user unless drivers.include?(user)
        end
      end

      riders = []
      if rider_emoji
        r_users = message.reaction_users(rider_emoji.to_reaction) || []
        r_users.concat(message.reaction_users(rider_emoji.modal_display) || [])
        r_users.uniq.each do |u|
          next if u.bot_account
          user = User.find_by(discord_id: u.id)
          next unless user&.rider?
          next if drivers.include?(user)
          EventSignup.find_or_create_by!(event: event, user: user, emoji: rider_emoji) do |es|
            es.response_type = :rider
          end
          riders << user unless riders.include?(user)
        end
      end

      summary = "Reaction details for event: #{event}\n"
      summary += "Drivers: #{drivers.map(&:name).join(', ')}\n"
      summary += "Riders: #{riders.map(&:name).join(', ')}\n"

      if riders.any? && drivers.any?
        @matcher = AppManager::Matcher.new(@bot.client)
        assignments, unassigned_riders = @matcher.match_riders_to_drivers(event, riders, drivers)
        assignment_text = assignments.map { |a|
          "#{a[:driver].name}: #{a[:riders].map(&:name).join(', ')}"
        }.join("\n")
        summary += "\nRide Assignments:\n#{assignment_text}\n"
        summary += "Unassigned Riders: #{unassigned_riders.map(&:name).join(', ')}" if unassigned_riders.any?
      end

      @bot.dm_mods summary
    end

    def schedule_existing_events
      Event.upcoming.unscheduled.each do |event|
        next unless event.schedulable?

        begin
          event.update!(rides_message_id: nil) unless @bot.client.channel(event.channel.discord_id).load_message(event.rides_message_id)
        rescue ArgumentError
          event.update!(rides_message_id: nil)
        end

        schedule(event)
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
      event = Event.find(event.id)
      return unless event.scheduled? && !event.cancelled? && event.rides_message_id.nil?

      rides_message = @bot.client.send(event.channel.discord_id, event.message)
      event.emojis.each do |emoji|
        rides_message.react emoji
      end
      event.update!(rides_message_id: rides_message.id)
    end

    def task_scheduler
      @scheduler.every '5 minutes' do
        schedule_existing_events
      end
    end
  end
end
