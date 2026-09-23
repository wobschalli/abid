module Signup
  # Builds the exact text the bot will post.
  #
  # Deterministic and side-effect free, and used by BOTH the dashboard preview
  # and the publisher — so what a coordinator approves is byte-for-byte what
  # lands in the channel.
  class MessageRenderer
    # The Discord role every sign-up pings. Looked up by name because roles are
    # synced from the server by Bot::Setup; if it is ever renamed or deleted
    # the message simply goes out without a ping rather than failing.
    PING_ROLE = 'Riders'.freeze

    def self.ping_role
      Role.where('lower(name) = ?', PING_ROLE.downcase).first
    end

    # What the publisher must pass as allowed_mentions: this role and nothing
    # else, so a stray @everyone typed into an intro can never ping anyone.
    def self.allowed_mentions
      role = ping_role
      { parse: [], roles: role ? [role.discord_id.to_s] : [] }
    end

    def initialize(post)
      @post = post
    end

    def to_s
      [intro, option_lines, outro].compact_blank.join("\n\n")
    end

    private

    # Every sign-up opens with the Riders ping — the default wording and a
    # hand-written intro alike. A coordinator who typed the mention in
    # themselves is not pinged twice.
    def intro
      text = @post.intro.presence || default_intro
      ping = self.class.ping_role&.then { |role| "<@&#{role.discord_id}>" }
      return text if ping.nil? || text.include?(ping) || text.match?(/\A@#{PING_ROLE}\b/i)

      "#{ping} #{text}"
    end

    def default_intro
      "react to this message if you would like a ride to #{destination}!"
    end

    # "Friday night Abide" is what people call Friday; any other day is named
    # by its events, so a Sunday post reads "Sunday School or Sunday Service".
    def destination
      events = @post.options.filter_map(&:event)
      date = @post.service_date || events.filter_map(&:start_time).min&.to_date
      return 'Friday night Abide' if date&.friday?

      names = events.map(&:name).compact_blank.uniq
      names.empty? ? 'church' : names.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')
    end

    def option_lines
      lines = @post.options.map { |option| line_for(option) }
      return nil if lines.empty?

      lines.join("\n")
    end

    def line_for(option)
      "#{option.mention}  #{option.label.presence || derived_label(option)}"
    end

    # Falls back to the occurrence itself, so an option is never a bare emoji
    # with nothing next to it.
    def derived_label(option)
      event = option.event
      return 'need a ride' if event.nil?

      time = event.start_time&.strftime('%-l:%M %p')
      [time, event.name].compact_blank.join(' — ')
    end

    def outro
      @post.outro.presence
    end
  end
end
