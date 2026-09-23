class SignupOption < ApplicationRecord
  # One emoji on a sign-up post, and the occurrence it books.
  #
  # Discord can tell us which emoji are on a message and how many people used
  # each. It cannot tell us that 1️⃣ means "the 9:00am ride to Sunday School".
  # That is the only thing this table exists to record.
  belongs_to :signup_post
  belongs_to :event, optional: true
  has_many :signup_reactions, dependent: :destroy

  validates :emoji_key, presence: true, uniqueness: { scope: :signup_post_id }
  # An event_id pointing at a row that does not exist (a stale form, a crafted
  # request) would otherwise surface as a PG::ForeignKeyViolation and a 500.
  # The association resolves to nil, so presence catches it as a 422.
  validates :event, presence: true, if: -> { event_id.present? }

  scope :published, -> { where.not(discord_message_id: nil) }
  scope :bound, -> { where.not(event_id: nil) }
  scope :unbound, -> { where(event_id: nil) }

  # The gateway hot path: one index scan, no join. Returns nil for the ~95% of
  # reactions in the server that are on messages we do not care about.
  def self.for_reaction(message_id, emoji_key)
    find_by(discord_message_id: message_id, emoji_key: emoji_key)
  end

  def custom?
    emoji_discord_id.present?
  end

  # What Discordrb::Message#react wants: the raw unicode character, or
  # "name:id" for a server emoji.
  def to_reaction
    custom? ? "#{emoji_name}:#{emoji_discord_id}" : emoji_unicode
  end

  # What renders as the emoji inside message text. Animated emoji need the
  # leading `a` or they render broken.
  def mention
    return emoji_unicode unless custom?

    "<#{'a' if emoji_animated}:#{emoji_name}:#{emoji_discord_id}>"
  end

  def display
    emoji_unicode.presence || ":#{emoji_name}:"
  end

  def live_reaction_count
    signup_reactions.where(removed_at: nil).count
  end

  def bound?
    event_id.present?
  end
end
