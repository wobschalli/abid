module Signup
  # Re-reads a sign-up post's reactions and repairs any drift.
  #
  # Gateway events get dropped — during a restart, a resume, a network blip. If
  # reactions were the only input, people would silently vanish from the board.
  # This runs periodically, on demand, and once at boot; the boot run is the
  # real answer to everything missed while the bot was down.
  #
  # The cheap path matters. A fetched message carries a reaction count per emoji
  # (Discordrb::Reaction#count), so ONE request tells us whether anything moved.
  # Only an emoji whose count disagrees with our tally costs the paginated
  # user-list fetch. In the steady state that is one request per post, not one
  # per option.
  class Reconciler
    Report = Struct.new(:post, :status, :added, :removed, :checked, :fetched, keyword_init: true)

    def initialize(bot, sink: nil)
      @bot = bot
      @sink = sink || ReactionSink.new
    end

    def run_all(scope = SignupPost.tracking)
      scope.includes(:channel, :options).map { |post| run(post) }
    end

    def run(post)
      return Report.new(post: post, status: :skipped) unless post.open? && post.options.any?

      message = load_message(post)
      if message.nil?
        # Nothing used to act on this, so a post whose message had been deleted
        # stayed `tracking` and was re-fetched every tick until the end of term,
        # logging an error each time. Stop polling something Discord has told us
        # is gone — but only when it said so definitively (see `load_message`).
        close_vanished(post) if @vanished
        return Report.new(post: post, status: :message_gone)
      end

      report = Report.new(post: post, status: :ok, added: 0, removed: 0, checked: 0, fetched: 0)
      counts = counts_by_key(message)

      post.options.each do |option|
        report.checked += 1
        next if in_sync?(option, counts)

        report.fetched += 1
        sync_option(post, option, message, report)
      end

      reseed_missing_reactions(message, post, counts)
      post.update!(reconciled_at: Time.zone.now, reconcile_requested_at: nil)
      report
    rescue StandardError => e
      warn "reconcile of post #{post.id} failed: #{e.class}: #{e.message}"
      Report.new(post: post, status: :error)
    end

    private

    # Discord says "this will never exist again" with these. Everything else —
    # a 500, a timeout, a severed socket — is transient and must NOT stop us
    # tracking the post.
    #
    # Resolved lazily rather than as a constant: `load_services` loads this file
    # into the *web* process too, which does not require discordrb, and naming
    # those classes in a class body would turn every page into a NameError.
    def definitively_gone?(error)
      return false unless defined?(Discordrb::Errors)

      [Discordrb::Errors::UnknownMessage,
       Discordrb::Errors::UnknownChannel].any? { |klass| error.is_a?(klass) }
    end

    # nil means the message is gone or unreachable. Never fall through to the
    # diff loop on a transient API failure — that would mass-cancel every ride.
    # Sets @vanished when the failure is permanent, so the caller can stop
    # polling without also treating a network blip as a deletion.
    def load_message(post)
      @vanished = false
      channel = @bot.channel(post.channel.discord_id)

      if channel.nil?
        # `@bot.channel` returns nil rather than raising for a channel the bot
        # cannot see, so this used to surface as `NoMethodError: undefined
        # method 'load_message' for nil` — which reads like a code bug and says
        # nothing about the actual cause.
        @vanished = true
        warn "channel #{post.channel.discord_id} (##{post.channel.name}) is not visible to the bot"
        return nil
      end

      channel.load_message(post.discord_message_id)
    rescue StandardError => e
      if definitively_gone?(e)
        @vanished = true
        warn "message #{post.discord_message_id} is gone: #{e.class}"
      else
        warn "could not load message #{post.discord_message_id}: #{e.class}: #{e.message}"
      end
      nil
    end

    # Closing stops the polling and shows up in the dashboard as closed. It
    # deliberately leaves every existing reaction, signup and ride alone: the
    # riders really did sign up, and the ride board is the record of that even
    # once the post behind it is deleted.
    def close_vanished(post)
      return unless post.open?

      post.close!
      post.update(last_error: 'sign-up message no longer exists on Discord')
      warn "closed sign-up post #{post.id}: message no longer exists"
    end

    # { emoji_key => count_excluding_our_own_seed_reaction }
    def counts_by_key(message)
      message.reactions.to_h do |reaction|
        # `count` includes the bot's own seed reaction; `me` says whether we
        # added it. Miss this and every option reads permanently one over.
        [EmojiKey.from_reaction(reaction), reaction.count - (reaction.me ? 1 : 0)]
      end
    end

    def in_sync?(option, counts)
      counts.fetch(option.emoji_key, 0) == option.signup_reactions.live.count
    end

    def sync_option(post, option, message, report)
      present = reactor_ids(message, option)
      return if present.nil? # fetch failed; leave this option alone

      live = option.signup_reactions.live.pluck(:discord_user_id)

      (present - live).each do |discord_user_id|
        result = @sink.add(message_id: post.discord_message_id, emoji_key: option.emoji_key,
                           discord_user_id: discord_user_id, source: 'reconcile')
        report.added += 1 unless result.status == :ignored
      end

      (live - present).each do |discord_user_id|
        result = @sink.remove(message_id: post.discord_message_id, emoji_key: option.emoji_key,
                              discord_user_id: discord_user_id, source: 'reconcile')
        report.removed += 1 unless result.status == :ignored
      end

      option.update!(synced_at: Time.zone.now, discord_message_id: post.discord_message_id)
    end

    # `limit: nil` makes discordrb paginate past the 100-reactor cap. Do not use
    # all_reaction_users: it is hard-capped and throws away which emoji each
    # person used, which is the entire signal here.
    def reactor_ids(message, option)
      message.reacted_with(option.to_reaction, limit: nil)
             .reject(&:bot_account?)
             .map(&:id)
    rescue StandardError => e
      warn "could not fetch reactors for #{option.emoji_key}: #{e.class}: #{e.message}"
      nil
    end

    # Someone cleared the reactions, or the bot never managed to add them. Put
    # the clickable options back so newcomers have something to react to.
    def reseed_missing_reactions(message, post, counts)
      return unless post.posted?

      post.options.each do |option|
        next if counts.key?(option.emoji_key)

        message.react(option.to_reaction)
        sleep 0.3 # stay under Discord's per-message reaction rate limit
      rescue StandardError => e
        warn "could not re-seed #{option.emoji_key}: #{e.class}: #{e.message}"
      end
    end
  end
end
