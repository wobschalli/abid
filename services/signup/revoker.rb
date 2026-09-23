module Signup
  # Takes a posted sign-up back down: deletes the Discord message, clears the
  # reactions it collected, and returns the post to an editable draft.
  #
  # For the case the app had no answer to at all — you post the sign-up, read it
  # back, and the emoji point at the wrong services. Until this existed the only
  # remedy was deleting the message by hand in Discord, after which the app
  # still believed it was posted and kept polling it forever.
  #
  # Runs in the BOT, because the web process has no Discord connection. The
  # ordering is the whole design: the post stays `posted` until the message is
  # confirmed gone. Flipping it to draft first and tidying Discord up afterwards
  # would mean that with the bot down you are editing a draft while the original
  # is still live in the channel — and pressing Post now puts a SECOND message
  # up beside the first, which is worse than the problem being fixed.
  class Revoker
    include MessageLookup

    Result = Struct.new(:post, :status, keyword_init: true)

    def initialize(bot, sink: nil)
      @bot = bot
      @sink = sink || ReactionSink.new
    end

    def run_all(scope = SignupPost.revoke_requested)
      scope.includes(:channel, :options).map { |post| run(post) }
    end

    def run(post)
      message = load_message(post)

      # Already gone counts as done. A coordinator who deleted it in Discord
      # first and then pressed Revoke must not be stuck with a post the app
      # thinks is live — the end state is what matters, not who did it.
      return finish(post, :already_gone) if message.nil? && vanished?

      # Anything else is Discord having a bad moment. Leave the flag set so the
      # next sweep tries again, and leave the post `posted` so nothing is
      # half-done and no second message can be sent.
      return Result.new(post: post, status: :deferred) if message.nil?

      message.delete
      finish(post, :revoked)
    rescue StandardError => e
      return finish(post, :already_gone) if definitively_gone?(e)

      warn "could not revoke signup post #{post.id}: #{e.class}: #{e.message}"
      Result.new(post: post, status: :failed)
    end

    private

    # Reactions first, ids second.
    #
    # `remove_all` finds the options by discord_message_id, so clearing the ids
    # before it runs would leave every reaction and ride in place while the post
    # looked freshly drafted — the exact silent half-done state this is built to
    # avoid. In one transaction so a crash between the two cannot produce it
    # either.
    def finish(post, status)
      message_id = post.discord_message_id

      SignupPost.transaction do
        @sink.remove_all(message_id: message_id) if message_id
        post.revoke!
      end

      warn "revoked signup post #{post.id} (#{status})"
      Result.new(post: post, status: status)
    end
  end
end
