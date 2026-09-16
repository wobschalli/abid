module Signup
  # Fills a sign-up post with one emoji row per event on its ride date.
  #
  # Every event that Sunday is already known, so asking a coordinator to pick
  # each one out of a dropdown of everything on the calendar was work the app
  # could do itself. A seeded post arrives already `bound?`, which leaves the
  # send time as the only thing left to decide.
  #
  # Idempotent by design, because it runs both on create and from a button: an
  # event that already has a row on this post is skipped, and so is an emoji
  # already in use. `signup_options` is uniquely indexed on
  # `[signup_post_id, emoji_key]`, so picking an emoji that is already there
  # would be a 500 rather than a duplicate.
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
      return [] if @post.service_date.blank? || !@post.editable?

      missing = events_for_date - @post.options.filter_map(&:event)
      return [] if missing.empty?

      missing.filter_map { |event| build(event) }
    end

    private

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
