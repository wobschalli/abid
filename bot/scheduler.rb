require_relative 'hfile'
require_relative 'bot'

class Bot
  class Scheduler
    def initialize(bot)
      @scheduler = Rufus::Scheduler.new(discard_past: false)
      @bot = bot
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
      if event && event.enabled? && event.rides_message_id
        reaction_users = @bot.channel(event.channel.discord_id).load_message(event.rides_message_id).all_reaction_users
        message = "reaction details for event: #{event}\n"
        message += reaction_users.map do |emoji, users|
          event.users = users.map do |reaction_user|
            reaction_user.bot_account? ? nil : User.find_by(discord_id: reaction_user.id)
          end.delete_if{ _1.nil? }

          "#{emoji}: #{users.join(", ")}"
        end.join("\n")
        @messenger.dm_ian message
        # @messenger.dm_alan message #lol
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
