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

    # @return [Array<Result>] the posts this run created or rescued
    def call
      uncovered_dates.filter_map { |date, events| create_for(date, events) } +
        rescue_own_drafts
    end

    # Drafts the automation itself created and then abandoned.
    #
    # A post made for a date that had no events yet is not schedulable, so it
    # was left as a draft — and when the events appeared later, nothing ever
    # re-attempted schedule!. The result was a fully-bound draft with a future
    # send time that would silently never send: the sign-up for an ordinary
    # Friday, missing, with every page implying it was handled.
    #
    # An earlier version of this rescue was removed because it could not tell
    # an abandoned draft from one a human was still writing, and scheduling
    # someone's half-edited post out from under them is worse. The
    # discriminator that was missing then is created_by: automation's own
    # posts carry nil, every human-created draft carries a user id. Rescuing
    # only your own abandoned children breaks no promise to anyone.
    def rescue_own_drafts
      SignupPost.includes(:options)
                .where(status: 'draft', created_by_id: nil)
                .where(service_date: @now.to_date..(@now + @horizon_weeks.weeks).to_date)
                .filter_map { |post| rescue_draft(post) }
    end

    # Set a single date up now, rather than waiting for it to come into the
    # three-week window: create the post, seed its emoji rows, and schedule it
    # for the series' usual send time. What the calendar click calls.
    #
    # Idempotent by design — clicking the same day twice reaches the same post.
    # It deliberately does NOT reach through `@horizon_weeks`: the point is to
    # set up a date that is further out than the automation would reach yet.
    #
    # @return [SignupPost, nil] nil when the date has no events, or no channel
    def ensure_for(date)
      date = date.to_date
      existing = SignupPost.where.not(status: 'failed').find_by(service_date: date)
      return existing if existing

      events = Event.active.where(start_time: date.all_day).chronological.to_a
      return nil if events.empty?

      create_for(date, events)&.post
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

    def rescue_draft(post)
      events = Event.active.where(start_time: post.service_date.all_day).chronological.to_a
      return nil if events.empty?

      OptionSeeder.new(post).call if post.options.empty?
      post.reload

      series = events.filter_map(&:series).first
      post.update(post_at: series.signup_post_at(post.service_date)) if post.post_at.nil? && series

      return nil unless post.ready_to_send?
      return nil if post.post_at.nil? || post.post_at <= @now

      post.schedule! ? Result.new(post: post, scheduled: true) : nil
    end

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
      @default_channel ||= Channel.for_rides.count == 1 ? Channel.for_rides.first : nil
    end
  end
end
