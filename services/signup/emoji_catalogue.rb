require 'tanuki_emoji'

module Signup
  # Every emoji a coordinator can pick, in one searchable list.
  #
  # The free-text box always accepted any emoji — `EmojiKey.parse` handles the
  # whole Unicode set, `:alpha_codes:` and `<:custom:id>`. What was missing was
  # a way to FIND one: the picker offered 28 hand-chosen characters, so anything
  # else meant knowing its name and typing it blind.
  #
  # Served as JSON from its own endpoint rather than inlined in the page. It is
  # ~150KB and identical for every sign-up, so inlining it would put that on
  # every page load of a form whose usual interaction is picking 1️⃣ and 2️⃣.
  # From an endpoint the browser caches it once.
  module EmojiCatalogue
    # Skin-tone variants of the same gesture — 1880 of the 3782, all of them
    # near-duplicates in a grid. Discord's own picker shows one base emoji and a
    # separate tone control; five copies of every waving hand is a worse list,
    # not a more complete one. Anyone who wants a specific tone can still type
    # or paste it, which has always worked.
    SKIN_TONES = /[\u{1F3FB}-\u{1F3FF}]/
    # Tone swatches and hair components: not emoji anyone reacts with.
    SKIP_CATEGORIES = ['Component'].freeze

    module_function

    # @return [Array<Hash>] { c: character, n: name, k: search keywords, g: group }
    def unicode
      @unicode ||= TanukiEmoji.index.all.filter_map do |emoji|
        next if emoji.codepoints.match?(SKIN_TONES)
        next if SKIP_CATEGORIES.include?(emoji.category.to_s)

        { c: emoji.codepoints, n: emoji.name.to_s, k: keywords(emoji), g: emoji.category.to_s }
      end
    end

    # The server's own emoji, in the same shape so the picker can search across
    # both. `v` is what gets submitted — Discord's own `<:name:id>` form, which
    # `EmojiKey.parse` already understands — and `u` is the image to draw,
    # because a custom emoji has no character to print.
    def custom(server_emojis)
      server_emojis.map do |emoji|
        { c: ":#{emoji.name}:", v: "<:#{emoji.name}:#{emoji.discord_id}>",
          n: emoji.name.to_s, k: emoji.name.to_s.tr('_', ' '), g: 'This server',
          u: "https://cdn.discordapp.com/emojis/#{emoji.discord_id}.png?size=32" }
      end
    end

    def all(server_emojis = [])
      custom(server_emojis) + unicode
    end

    # What typing in the search box matches against: the short name, the
    # human description, and every alias. "car" should find 🚗 whether the
    # coordinator thinks of it as `car`, `red car` or `automobile`.
    def keywords(emoji)
      [emoji.name, emoji.description, *emoji.aliases]
        .compact
        .map { |word| word.to_s.delete(':').tr('_', ' ') }
        .uniq
        .join(' ')
        .downcase
    end
  end
end
