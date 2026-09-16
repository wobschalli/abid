module Signup
  # Creates and schedules the sign-up post for every upcoming ride date.
  #
  # Recurrence used to stop halfway: EventSeries -> Event was automatic, but
  # Event -> SignupPost was a weekly hand-click, and every keystroke it asked
  # for was the same as last week's. This closes the gap, so the steady-state
  # weekly workload is nothing at all — the coordinator opens the board once
  # reactions have landed.
  #
  # Runs from the bot's daily occurrence sweep, and again whenever a series is
  # created or edited so the result is visible immediately.
  class AutoSchedule
    Result = Struct.new(:post, :scheduled, keyword_init: true)

    def initialize(horizon_weeks: 3, now: nil)
      @horizon_weeks = horizon_weeks
      @now = now || Time.zone.now
    end

    # @return [Array<Result>] only the posts this run created
    def call
      uncovered_dates.filter_map { |date, events| create_for(date, events) }
    end

    # Upcoming dates that have active events and no sign-up post yet.
    #
    # Shared with the schedule page so the list you are shown and the list that
    # gets acted on cannot disagree.
    def uncovered_dates
      events = Event.active.includes(:series, :channel)
                    .where(start_time: @now..(@now + @horizon_weeks.weeks))
                    .chronological.to_a
      return [] if events.empty?

      by_date = events.group_by { |event| event.start_time.to_date }
      # Judged by service_date rather than by the options' events: a post
      # someone made but has not filled in yet still counts, or the date would
      # keep offering to make a second one.
      covered = SignupPost.where.not(status: 'failed')
                          .where(service_date: by_date.keys)
                          .pluck(:service_date)

      by_date.reject { |date, _| covered.include?(date) }.sort_by(&:first)
    end

    private

    def create_for(date, events)
      series = events.filter_map(&:series).first
      channel = events.filter_map(&:channel).first || series&.channel || default_channel
      return nil if channel.nil?

      post = SignupPost.create(
        channel: channel,
        service_date: date,
        outro: series&.signup_outro.presence,
        status: 'draft'
      )
      return nil unless post.persisted?

      OptionSeeder.new(post).call
      Result.new(post: post, scheduled: schedule(post, date, series))
    end

    # Only ever schedules into the future. A series added two days before its
    # first occurrence computes a send time that has already passed, and
    # back-dating that into a 271-person server on the next tick is not a thing
    # to do quietly — those wait as drafts for a human to press Post now.
    def schedule(post, date, series)
      return false if series.nil?

      post_at = series.signup_post_at(date)
      return false if post_at <= @now

      post.update(post_at: post_at)
      post.reload.schedule!
    end

    # With a single channel configured there is nothing to choose. With none,
    # `create_for` gives up rather than guessing where to post.
    def default_channel
      @default_channel ||= Channel.count == 1 ? Channel.first : nil
    end
  end
end
