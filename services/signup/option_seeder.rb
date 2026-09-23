module Signup
  # Keeps a sign-up post at exactly one emoji row per pickup time on its date.
  #
  # Every time that day is already known, so assembling the list by hand was
  # work the app could do itself — and work that could be got wrong. A synced
  # post arrives already `bound?`, which leaves the send time as the only thing
  # to decide.
  #
  # It used to only ADD. That made "one row per time" true at the moment a post
  # was created and drifting from then on: cancel the 5:30 and its emoji stayed
  # on the message, still collectable, booking a ride that was not happening.
  # Now it prunes too, which is what makes the rule actually hold.
  #
  # Idempotent, because it runs on create and on every page view: a time that
  # already has a row is left alone, and so is an emoji already in use.
  # `signup_options` is uniquely indexed on `[signup_post_id, emoji_key]`, so
  # reusing one would be a 500 rather than a duplicate.
  class OptionSeeder
    # Keycaps in order, so the first ride of the day is 1️⃣. Ten is far more
    # than any real Sunday, and running out is handled rather than raised.
    DEFAULT_EMOJI = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣',
                     '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟'].freeze

    def initialize(post)
      @post = post
    end

    # @return [Array<SignupOption>] only the rows this call created
    def call
      # Never on a post that has gone out. Its emoji are live on a Discord
      # message with people's reactions attached, and dropping one here would
      # orphan them — the coordinator revokes it instead.
      return [] if @post.service_date.blank? || !@post.editable?

      prune
      missing = events_for_date - @post.options.filter_map(&:event)
      return [] if missing.empty?

      missing.filter_map { |event| build(event) }
    end

    private

    # Rows that break "one per time": a time that is gone, and a time that has
    # more than one row.
    #
    # The duplicate half is not hypothetical — this post had two rows for the
    # 9:30 and two for the 10:30, so the message offered four emoji for two
    # rides. Without this the page shows them forever, because every one of
    # them points at a real time and nothing else would remove them.
    #
    # The survivor is the lowest position, which is the oldest: that is the row
    # carrying the emoji and the line of text somebody chose, so a duplicate
    # added later loses rather than overwriting their work.
    def prune
      live = events_for_date.map(&:id)
      seen = []

      doomed = @post.options.sort_by { |option| [option.position || 0, option.id] }.reject do |option|
        next false unless live.include?(option.event_id)
        next false if seen.include?(option.event_id)

        seen << option.event_id
        true
      end
      return if doomed.empty?

      doomed.each(&:destroy)
      @post.options.reset
      @taken = nil
    end

    def events_for_date
      Event.active
           .where(start_time: @post.service_date.all_day)
           .chronological
           .to_a
    end

    def build(event)
      attrs = next_emoji or return nil

      option = @post.options.create(
        attrs.merge(event: event, position: @post.options.size)
      )
      option.persisted? ? option : nil
    end

    # Walks past anything already on the post, so seeding a post a coordinator
    # has already hand-edited adds to it rather than colliding with it.
    def next_emoji
      DEFAULT_EMOJI.each do |char|
        attrs = EmojiKey.parse(char) or next
        next if taken.include?(attrs[:emoji_key])

        taken << attrs[:emoji_key]
        return attrs
      end
      nil
    end

    # A plain Array, not a Set: this is at most ten entries, and `to_set` would
    # add a `require 'set'` that this file does not otherwise need.
    def taken
      @taken ||= @post.options.map(&:emoji_key).compact
    end
  end
end
