# Required here rather than relying on bot/hfile.rb: the web process loads
# services but not the bot's require list, and both halves parse emoji.
require 'tanuki_emoji'

module Signup
  # Canonical identity for an emoji, so that what a coordinator typed and what
  # Discord delivers on a reaction collapse to the same string.
  #
  # Two problems this solves:
  #
  # 1. Discord sends keycaps with or without U+FE0F. "1️⃣" and
  #    "1⃣" are different byte sequences for the same emoji. Routing both
  #    through TanukiEmoji collapses them to "one".
  # 2. TanukiEmoji's index is incomplete — `:car:` and `:car_side:` are not in
  #    it — so anything unrecognised falls back to its raw characters. Compose
  #    time and reaction time run this same function, so they still agree.
  module EmojiKey
    # <:name:id> or <a:name:id> for animated
    CUSTOM_PATTERN = /<(a)?:(\w{2,32}):(\d{15,25})>/
    # Digit/#/* keycaps: the variation selector is optional.
    KEYCAP_PATTERN = /[0-9#*]\u{FE0F}?\u{20E3}/
    # Everything with default emoji presentation, plus skin tones and ZWJ
    # sequences so a compound emoji is captured whole rather than in pieces.
    UNICODE_PATTERN = /\p{Emoji_Presentation}(?:\p{Emoji_Modifier})?(?:\u{200D}\p{Emoji}(?:\u{FE0F})?)*/
    # A bare :alpha_code: typed by a coordinator.
    ALPHA_PATTERN = /\A:?([a-z0-9_+-]{1,64}):?\z/i

    SCAN_PATTERN = Regexp.union(CUSTOM_PATTERN, KEYCAP_PATTERN, UNICODE_PATTERN)

    module_function

    # @param str [String] the literal emoji characters
    # @return [String] "u:one", or "u:🚙" when TanukiEmoji has never heard of it
    def for_unicode(str)
      return nil if str.blank?

      "u:#{TanukiEmoji.find_by_codepoints(str)&.name || str}"
    end

    # @param discord_id [Integer, String]
    def for_custom(discord_id)
      "c:#{discord_id}"
    end

    # @param event [Discordrb::Events::ReactionEvent]
    def from_reaction_event(event)
      emoji = event.emoji
      emoji.id ? for_custom(emoji.id) : for_unicode(emoji.name)
    end

    # @param reaction [Discordrb::Reaction] from Message#reactions
    def from_reaction(reaction)
      reaction.id ? for_custom(reaction.id) : for_unicode(reaction.name)
    end

    # Pull every emoji out of a message, in the order they appear, deduplicated.
    # This is how the bot learns which options a coordinator offered.
    #
    # @return [Array<Hash>] attribute hashes ready for SignupOption
    def scan(content)
      return [] if content.blank?

      seen = {}
      content.to_s.scan(SCAN_PATTERN) do
        token = Regexp.last_match(0)
        attrs = describe(token)
        next if attrs.nil?

        seen[attrs[:emoji_key]] ||= attrs
      end
      seen.values
    end

    # Coordinator free text: a literal emoji, :alpha_code:, alpha_code, or
    # <:name:id>. Returns nil when nothing resolves, so a caller can complain.
    def parse(input)
      text = input.to_s.strip
      return nil if text.empty?

      describe(text) || from_alpha_code(text)
    end

    # Is this string entirely one emoji? `scan` has already matched the pattern,
    # but `parse` takes arbitrary coordinator text, and without this check the
    # raw-string fallback in `for_unicode` happily turns "garbage!!" into the
    # key "u:garbage!!".
    def emoji?(token)
      token.to_s.match?(/\A(?:#{KEYCAP_PATTERN}|#{UNICODE_PATTERN})\z/)
    end

    # @return [Hash, nil] attributes for one token
    def describe(token)
      if (match = CUSTOM_PATTERN.match(token))
        return {
          emoji_key: for_custom(match[3]),
          emoji_unicode: nil,
          emoji_name: match[2],
          emoji_discord_id: match[3].to_i,
          emoji_animated: match[1].present?
        }
      end

      return nil unless emoji?(token)

      key = for_unicode(token)
      return nil if key.nil?

      {
        emoji_key: key,
        emoji_unicode: token,
        emoji_name: TanukiEmoji.find_by_codepoints(token)&.name,
        emoji_discord_id: nil,
        emoji_animated: false
      }
    end

    def from_alpha_code(text)
      match = ALPHA_PATTERN.match(text) or return nil
      character = TanukiEmoji.find_by_alpha_code(":#{match[1].downcase}:")
      return describe(character.codepoints) if character

      # Fall back to the server's own emoji catalogue.
      emoji = Emoji.find_by(name: match[1])
      return nil if emoji.nil?

      {
        emoji_key: for_custom(emoji.discord_id),
        emoji_unicode: nil,
        emoji_name: emoji.name,
        emoji_discord_id: emoji.discord_id,
        emoji_animated: false
      }
    end
  end
end
