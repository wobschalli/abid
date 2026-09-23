module Signup
  # Fetching the Discord message behind a sign-up post, and telling "it is gone"
  # apart from "Discord did not answer".
  #
  # Extracted so the reconciler and the revoker share one copy. They ask the
  # same question for opposite reasons — one wants to read the reactions, the
  # other wants to delete the thing — and a second, subtly different version of
  # this would be a bug waiting to happen: both hinge on `vanished?`, and both
  # do something irreversible when it is true.
  module MessageLookup
    # Discord says "this will never exist again" with these. Everything else —
    # a timeout, a 500, a rate limit — is a bad moment, not a deletion.
    def definitively_gone?(error)
      return false unless defined?(Discordrb::Errors)

      [Discordrb::Errors::UnknownMessage,
       Discordrb::Errors::UnknownChannel].any? { |klass| error.is_a?(klass) }
    end

    # nil means the message is gone or unreachable. Never fall through to acting
    # on a transient API failure — for the reconciler that would mass-cancel
    # every ride; for the revoker it would report a message deleted that is
    # still sitting in the channel.
    #
    # Sets `vanished?` when the failure is permanent, so the caller can act
    # without also treating a network blip as a deletion.
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

      message = channel.load_message(post.discord_message_id)

      # discordrb rescues UnknownMessage itself and returns nil
      # (Discordrb::Channel#load_message), so the exception `definitively_gone?`
      # waits for never escapes. Nil from that call means exactly one thing —
      # the message is not there — and anything else still raises.
      #
      # Worth stating plainly because it defeated this code for a long time: the
      # reconciler's "stop polling a message Discord says is gone" branch could
      # not fire in production, and the revoker retried a deleted message every
      # fifteen seconds forever. Both tested green, because a hand-written fake
      # channel raises where the real one does not.
      if message.nil?
        @vanished = true
        warn "message #{post.discord_message_id} is gone (no such message)"
      end

      message
    rescue StandardError => e
      if definitively_gone?(e)
        @vanished = true
        warn "message #{post.discord_message_id} is gone: #{e.class}"
      else
        warn "could not load message #{post.discord_message_id}: #{e.class}: #{e.message}"
      end
      nil
    end

    def vanished?
      @vanished
    end
  end
end
