module Signup
  # Sends scheduled sign-up posts to Discord.
  #
  # Posting twice into a channel of eighty people is the only irreversible
  # failure in this feature, so the ordering here is deliberate:
  #
  #   1. claim the row atomically (FOR UPDATE SKIP LOCKED), status -> posting
  #   2. write rendered_body BEFORE sending, so a crash leaves a recovery key
  #   3. send
  #   4. mark_posted! (stamps the message id onto the options)
  #   5. add the reactions
  #
  # A crash between 3 and 4 is the dangerous window. `recover_stale` closes it
  # by looking for a message we already sent whose content matches
  # rendered_body, and adopting it instead of sending again.
  class Publisher
    REACTION_DELAY = 0.3 # stay under Discord's per-message reaction rate limit
    RECOVERY_SCAN = 50   # recent messages to search when recovering

    def initialize(bot)
      @bot = bot
    end

    # @return [Integer] how many posts were sent
    def run_once(limit: 3)
      recover_stale
      sent = 0
      limit.times do
        post = claim or break
        publish(post)
        sent += 1
      end
      sent
    end

    # A process killed mid-send leaves a row in `posting` forever.
    def recover_stale
      SignupPost.stale_posting.find_each do |post|
        adopted = find_already_sent(post)
        if adopted
          warn "adopting already-sent signup post #{post.id} (message #{adopted.id})"
          post.mark_posted!(adopted.id, body: post.rendered_body)
          seed_reactions(post, adopted)
        else
          # Nothing was sent; safe to try again.
          post.update!(status: 'scheduled')
        end
      rescue StandardError => e
        warn "recover_stale failed for post #{post.id}: #{e.class}: #{e.message}"
      end
    end

    private

    # The standard Postgres work-queue claim: safe against a second bot process
    # and against a crash between SELECT and UPDATE.
    def claim
      SignupPost.find_by_sql(<<~SQL).first
        UPDATE signup_posts
           SET status = 'posting', publish_attempts = publish_attempts + 1, updated_at = now()
         WHERE id = (
                 SELECT id FROM signup_posts
                  WHERE status = 'scheduled' AND post_at <= now()
                  ORDER BY post_at
                    FOR UPDATE SKIP LOCKED
                  LIMIT 1)
        RETURNING *
      SQL
    end

    def publish(post)
      body = MessageRenderer.new(post).to_s
      # Written before the send: this is what recover_stale matches on.
      post.update!(rendered_body: body)

      message = @bot.send(post.channel.discord_id, body, allowed_mentions: false)
      post.mark_posted!(message.id, body: body)
      seed_reactions(post, message)
    rescue StandardError => e
      warn "publishing signup post #{post.id} failed: #{e.class}: #{e.message}"
      post.mark_failed!("#{e.class}: #{e.message}")
    end

    # Giving people something to click. A failure here is not fatal — the
    # reconciler re-seeds any option whose reaction is missing.
    def seed_reactions(post, message)
      post.options.each do |option|
        message.react(option.to_reaction)
        sleep REACTION_DELAY
      rescue StandardError => e
        warn "could not seed #{option.emoji_key} on post #{post.id}: #{e.class}: #{e.message}"
      end
    end

    # Did we already send this? Matches on exact content among our own recent
    # messages in the channel.
    def find_already_sent(post)
      return nil if post.rendered_body.blank?

      @bot.channel(post.channel.discord_id)
          .history(RECOVERY_SCAN)
          .find { |m| m.author&.current_bot? && m.content == post.rendered_body }
    rescue StandardError => e
      warn "could not scan channel for recovery: #{e.class}: #{e.message}"
      nil
    end
  end
end
