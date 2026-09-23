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

    # How many sends to attempt before a post is declared failed and handed to
    # a human. Each retry waits out SignupPost::STALE_POSTING_AFTER (two
    # minutes), so this is a little over ten minutes of "the network is not
    # there yet" before giving up — long enough for a laptop that was asleep at
    # post time to wake and reconnect (seconds, usually), short enough that a
    # genuinely broken post is noticed the same evening.
    MAX_PUBLISH_ATTEMPTS = 6

    # Errors that mean "not right now", not "never". This is the shape of a
    # machine waking from sleep — the tick fires before DNS is back — and it is
    # how this Friday's sign-up was lost: one getaddrinfo failure at 08:24 and
    # the post was marked failed for good. Matched by ancestry name so nothing
    # here needs rest-client or openssl loaded to compare against.
    TRANSIENT_ERRORS = %w[
      Socket::ResolutionError SocketError IOError EOFError
      Errno::ECONNREFUSED Errno::ECONNRESET Errno::ETIMEDOUT Errno::EHOSTUNREACH
      Errno::ENETUNREACH Errno::EPIPE Errno::EAGAIN
      Net::OpenTimeout Net::ReadTimeout OpenSSL::SSL::SSLError
      RestClient::Exceptions::Timeout RestClient::ServerBrokeConnection
      RestClient::InternalServerError RestClient::BadGateway
      RestClient::ServiceUnavailable RestClient::GatewayTimeout RestClient::TooManyRequests
    ].freeze

    def self.transient?(error)
      error.class.ancestors.any? { |klass| TRANSIENT_ERRORS.include?(klass.name) }
    end

    def initialize(bot)
      @bot = bot
    end

    # @return [Integer] how many posts were sent
    def run_once(limit: 3)
      recover_stale
      sent = 0
      limit.times do
        post = claim or break
        next if abandon_cancelled(post)

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

    # A sign-up whose every event has been cancelled.
    #
    # Cancelling an occurrence switches the event off but never touched its
    # post, so a cancelled Friday still asked 271 people who wanted a lift to
    # it. The window for that used to be small because posts were only made
    # three days out; it is worth closing now that a date can be set up months
    # ahead from the calendar.
    #
    # Judged by the events the post's own options point at, NOT by matching
    # service_date against the day's events. The date version silently closed
    # any post whose date had drifted from its events — refusing to send is a
    # destructive answer to "I am not sure", so this only fires when the post
    # itself says which events it is for and every one of them is off.
    #
    # Closed rather than deleted: the post is the record that the date was once
    # planned, and `closed_at` already means "stop polling this".
    #
    # @return [true, false] whether the post was abandoned
    def abandon_cancelled(post)
      bound = post.options.filter_map(&:event)
      return false if bound.empty?
      return false if bound.any? { |event| !event.disabled }

      warn "signup post #{post.id} skipped — every event it covers is cancelled"
      post.update!(status: 'closed', closed_at: Time.zone.now)
      true
    end

    def publish(post)
      body = MessageRenderer.new(post).to_s
      # Written before the send: this is what recover_stale matches on.
      post.update!(rendered_body: body)

      message = @bot.send(post.channel.discord_id, body, allowed_mentions: false)
      post.mark_posted!(message.id, body: body)
      seed_reactions(post, message)
    rescue StandardError => e
      described = "#{e.class}: #{e.message}"
      if self.class.transient?(e) && post.publish_attempts < MAX_PUBLISH_ATTEMPTS
        # Leave it in `posting`. recover_stale owns that state: once the row
        # is stale it looks for a message we may already have sent — the send
        # could have succeeded and only the response been lost — and adopts
        # it, or puts the row back to `scheduled` for the next claim. That is
        # the retry, and it is the only retry path that cannot double-post.
        warn "publishing signup post #{post.id} hit a transient error (attempt #{post.publish_attempts}, will retry): #{described}"
        post.update!(last_error: described.first(255))
      else
        warn "publishing signup post #{post.id} failed: #{described}"
        post.mark_failed!(described)
      end
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
