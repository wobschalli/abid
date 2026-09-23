module Snipes
  # The one message in the snipes channel that carries the two buttons.
  #
  # Posted exactly once, then refreshed in place: the message id is kept on
  # the Channel row, and a re-run edits that message rather than adding a
  # second copy with a second pair of buttons. If the message has been
  # deleted by hand, `load_message` comes back nil (discordrb rescues
  # UnknownMessage itself — see Signup::MessageLookup) and it is posted anew.
  #
  # Runs inside the bot process, off an outbox flag the rake task sets — never
  # from a second gateway connection.
  class Notice
    Result = Struct.new(:status, :message_id, keyword_init: true)

    TEXT = <<~TEXT.strip
      📸 **Snipes**
      Spot someone on campus, snap them, post it here — and **@mention them**. Every snipe needs a tag; untagged ones are removed.

      Rather not be in the game? Press **Don't snipe me** and any snipe that tags you is taken down automatically. Changed your mind later? The other button puts you back in.
    TEXT

    OPT_OUT_ID = 'snipes_optout'.freeze
    OPT_IN_ID = 'snipes_optin'.freeze

    def initialize(bot)
      @bot = bot
    end

    # The tick's entry point: does nothing unless `rake snipes:post` asked.
    def post_requested!
      channel = Channel.notice_requested.find_by(purpose: 'snipes') or return nil
      result = post!(channel)
      channel.update!(notice_requested_at: nil)
      warn "snipes notice #{result.status} (message #{result.message_id}) in ##{channel.name}"
      result
    end

    def post!(channel = Channel.snipes)
      raise 'no snipes channel — run rake snipes:channel[ID]' if channel.nil?

      view = self.class.view
      existing = find_existing(channel)
      if existing
        existing.edit(TEXT, nil, view)
        Result.new(status: :refreshed, message_id: existing.id)
      else
        message = @bot.send(channel.discord_id, TEXT, components: view)
        channel.update!(notice_message_id: message.id)
        Result.new(status: :posted, message_id: message.id)
      end
    end

    # Static custom_ids: the buttons mean the same thing on every copy of the
    # message, so nothing has to be looked up to interpret a press. Guarded
    # because load_services pulls this file into the web process, which never
    # loads discordrb.
    def self.view
      return nil unless defined?(Discordrb::Webhooks::View)

      Discordrb::Webhooks::View.new.tap do |view|
        view.row do |row|
          row.button(label: "Don't snipe me", style: :danger, custom_id: OPT_OUT_ID, emoji: { name: '🙈' })
          row.button(label: "Changed my mind — I'm game", style: :success, custom_id: OPT_IN_ID, emoji: { name: '📸' })
        end
      end
    end

    private

    def find_existing(channel)
      return nil if channel.notice_message_id.nil?

      discord_channel = @bot.channel(channel.discord_id) or return nil
      discord_channel.load_message(channel.notice_message_id)
    rescue StandardError => e
      warn "snipes notice: could not load message #{channel.notice_message_id}: #{e.class}: #{e.message}"
      nil
    end
  end
end
