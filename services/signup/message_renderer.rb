module Signup
  # Builds the exact text the bot will post.
  #
  # Deterministic and side-effect free, and used by BOTH the dashboard preview
  # and the publisher — so what a coordinator approves is byte-for-byte what
  # lands in the channel.
  class MessageRenderer
    def initialize(post)
      @post = post
    end

    def to_s
      [intro, option_lines, outro].compact_blank.join("\n\n")
    end

    private

    def intro
      @post.intro.presence || default_intro
    end

    def default_intro
      date = @post.service_date || @post.options.filter_map { |o| o.event&.start_time }.min&.to_date
      return 'Rides — react below if you need one.' if date.nil?

      "Rides for #{date.strftime('%A %-d %B')} — react below if you need one."
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
