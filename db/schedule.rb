# Abide's actual weekly schedule, as the source of truth.
#
#   rake db:schedule          # report
#   rake db:schedule[apply]   # make the database match
#
# Anything not listed here is removed, along with its occurrences. That is the
# point: the five series the demo seeds left behind — Wednesday Prayer and a
# Friday "Bible Study" split into early/late — were invented, and kept
# generating ride boards nobody wanted.
#
# The Friday pair is dinner and the main gathering, which are separate pickups
# at different times, so they are two series the same way the two Sunday
# services are.
module Abid
  module Schedule
    SUNDAY = 0
    FRIDAY = 5

    # name, weekday, start time, section, sign-up lead days, send time, pickup,
    # driver tag
    #
    # Friday collects from the last class: people come straight from a lab, and
    # 42 of the 63 who told us both say those are different places. Sunday
    # morning everyone is at home.
    SERIES = [
      ['Abide dinner',   FRIDAY, '17:30', 'early', 3, '20:00', 'class', 'Friday-Usual'],
      ['Abide',          FRIDAY, '18:30', 'late',  3, '20:00', 'class', 'Friday-Usual'],
      ['Sunday School',  SUNDAY, '09:30', 'early', 3, '20:00', 'home',  'Sunday-Usual'],
      ['Sunday Service', SUNDAY, '10:30', 'late',  3, '20:00', 'home',  'Sunday-Usual']
    ].freeze

    module_function

    def call(apply: false)
      wanted = SERIES.map(&:first)
      stale = EventSeries.where.not(name: wanted)

      report_plan(stale)
      return unless apply

      # One transaction: a foreign key raising halfway through used to leave
      # some series gone, their events orphaned, and the replacements never
      # created.
      ActiveRecord::Base.transaction do
        remove(stale)
        SERIES.each { |row| upsert(row) }
      end

      EventGenerator.call
      created = Signup::AutoSchedule.new.call

      puts
      puts "series now: #{EventSeries.count}, events: #{Event.count}"
      puts "sign-ups auto-created: #{created.size} (#{created.count(&:scheduled)} scheduled)"
    end

    # `has_many :events, dependent: :nullify` orphans occurrences rather than
    # deleting them, which would leave ride boards floating with no series and
    # no way to reach them. Remove them explicitly.
    def remove(stale)
      stale.each do |series|
        events = Event.where(series_id: series.id)
        rides = Ride.where(event_id: events.select(:id))

        # `ride_id` is optional on a reaction but the foreign key is real, so a
        # reaction has to let go of its ride before the ride can go.
        SignupReaction.where(ride_id: rides.select(:id)).update_all(ride_id: nil)
        # Self-referential: a passenger row blocks the deletion of its own
        # driver unless the link is broken first.
        rides.update_all(driver_ride_id: nil)
        rides.delete_all

        SignupOption.where(event_id: events.select(:id)).update_all(event_id: nil)
        DispatchMessage.where(dispatch_id: Dispatch.where(event_id: events.select(:id)).select(:id)).delete_all
        Dispatch.where(event_id: events.select(:id)).delete_all
        events.delete_all
        series.destroy
      end
    end

    def upsert((name, weekday, start_at, section, lead_days, post_time, pickup, tag))
      series = EventSeries.find_or_initialize_by(name: name)
      series.assign_attributes(
        weekday: weekday, start_time_of_day: start_at, section: section,
        signup_lead_days: lead_days, signup_post_time: post_time,
        pickup_source: pickup,
        driver_tag: tag,
        interval_weeks: 1, horizon_weeks: 3, disabled: false,
        channel: series.channel || default_channel
      )
      series.save!
    end

    def default_channel
      Channel.count == 1 ? Channel.first : Channel.order(:id).first
    end

    def report_plan(stale)
      puts 'keeping / creating:'
      SERIES.each do |name, weekday, start_at, section, lead, at, pickup, tag|
        day = Date::DAYNAMES[weekday]
        puts "  #{day.ljust(9)} #{start_at}  #{name.ljust(16)} #{section.ljust(6)} " \
             "sends #{lead}d ahead at #{at}, collect from #{pickup}, drivers: #{tag}"
      end
      return if stale.none?

      puts
      puts 'removing (not in the list above):'
      stale.each do |series|
        events = Event.where(series_id: series.id)
        rides = Ride.where(event_id: events.select(:id)).count
        puts "  #{series.display_name.ljust(30)} #{events.count} events, #{rides} rides"
      end
    end
  end
end
