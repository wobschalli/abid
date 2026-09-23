module Snipes
  # The rule of the snipes channel, applied to one message.
  #
  # Every image posted there is a snipe. A snipe must @mention the person in
  # it — that is the only way the bot can tell whose photo it is — and a snipe
  # of anyone who has opted out is removed. Two consequences the caller must
  # not soften:
  #
  #   - An untagged image is removed AND the poster is told why, because the
  #     fix is theirs to make (tag them, post again).
  #   - A snipe of someone who opted out is removed silently. Telling the
  #     poster "they opted out" would announce exactly the thing the person
  #     asked not to have announced.
  #
  # Takes a discordrb Message (or anything shaped like one), and returns a
  # Result rather than a boolean so the handler can log what happened. Never
  # raises: a failed deletion is a status, and a failed DM is a warning. The
  # one thing this class refuses to do is tell someone their photo was removed
  # when it was not — no DM unless the delete succeeded.
  class Enforcer
    Result = Struct.new(:status, :mentioned, :deleted, keyword_init: true)

    # :not_snipes_channel  somewhere else; not our business
    # :not_a_snipe         no image, or a bot/webhook post
    # :ok                  tagged, and everyone tagged is fine with it
    # :untagged            image with no @mention — removed, poster told
    # :opted_out           tagged someone who opted out — removed, silently
    # :delete_failed       should have been removed, could not be
    STATUSES = %i[not_snipes_channel not_a_snipe ok untagged opted_out delete_failed].freeze

    # Discord's MESSAGE_CONTENT gateway intent. This discordrb fork has no
    # symbol for it; the intents calculator accepts the raw bit. Privileged:
    # it must also be switched on in the developer portal, or the gateway
    # refuses the connection.
    MESSAGE_CONTENT_INTENT = 1 << 15

    # The feature exists the moment a channel carries the snipes purpose, and
    # not before. Everything that costs something — the privileged intent, the
    # message handler doing work — keys off this, so a deploy with no snipes
    # channel configured is indistinguishable from a deploy without the code.
    # Rescues, because Messenger asks this at boot and a database without the
    # column yet (mid-migration, fresh install) must read as "not enabled".
    def self.enabled?
      Channel.snipes.present?
    rescue StandardError
      false
    end

    def initialize(bot)
      @bot = bot
    end

    def call(message)
      channel = Channel.snipes
      return result(:not_snipes_channel) unless channel && message.channel&.id == channel.discord_id

      author = message.author
      return result(:not_a_snipe) if author.nil? || author.bot_account?
      return result(:not_a_snipe) unless image?(message)

      mentioned = Array(message.mentions).map(&:id).uniq
      if mentioned.empty?
        return remove(message, mentioned, :untagged, reason: 'snipe without an @mention') do
          tell_poster(author, channel)
        end
      end

      if User.where(discord_id: mentioned, snipes_opt_out: true).exists?
        return remove(message, mentioned, :opted_out, reason: 'snipe of someone who opted out')
      end

      result(:ok, mentioned: mentioned)
    end

    private

    # An attached file Discord recognised as an image, or a pasted image URL
    # that Discord turned into an image embed. A link with a rich preview is
    # not a snipe; a file that is not an image is not a snipe.
    def image?(message)
      return true if Array(message.attachments).any? { |a| a.respond_to?(:image?) && a.image? }

      Array(message.embeds).any? do |embed|
        embed.respond_to?(:type) && embed.type.to_s == 'image' ||
          (embed.respond_to?(:image) && embed.image)
      end
    end

    def remove(message, mentioned, status, reason:)
      message.delete(reason)
      yield if block_given?
      result(status, mentioned: mentioned, deleted: true)
    rescue StandardError => e
      hint = e.class.name.to_s.include?('NoPermission') ? ' — the bot needs Manage Messages in this channel' : ''
      warn "snipes: could not delete message #{message.respond_to?(:id) ? message.id : '?'}: #{e.class}: #{e.message}#{hint}"
      result(:delete_failed, mentioned: mentioned, deleted: false)
    end

    def tell_poster(author, channel)
      @bot.user(author.id)&.dm(
        "Your photo in ##{channel.name} was removed. Snipes have to @mention the person " \
        'in them — that is how people who have opted out stay protected. Tag them and post it again.'
      )
    rescue StandardError => e
      # DMs closed is a normal outcome, not a failure of the rule.
      warn "snipes: could not DM #{author.id}: #{e.class}: #{e.message}"
    end

    def result(status, mentioned: [], deleted: false)
      Result.new(status: status, mentioned: mentioned, deleted: deleted)
    end
  end
end
