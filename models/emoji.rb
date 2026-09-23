class Emoji < ApplicationRecord
  # A catalogue of the Discord server's own custom emoji, synced by
  # Bot::Setup#setup_emojis. Used to populate the emoji picker when binding
  # sign-up options.
  #
  # This used to also hold unicode rows and carry an `event_id`, which made
  # `Event has_many :emojis` a one-to-many pretending to be a many-to-many:
  # assigning an emoji to one event silently stole it from another. Emoji
  # identity for sign-ups now lives inline on signup_options.
  belongs_to :server

  before_save :ensure_not_alpha_code

  scope :by_name, -> { order(:name) }

  def alpha_code
    ":#{name}:"
  end

  def to_reaction # use as a reaction in Discordrb::Message#react
    "#{name}:#{discord_id}"
  end

  def mention
    "<:#{name}:#{discord_id}>"
  end

  private

  # `self.name.remove ':'` was a silent no-op: String#remove is non-mutating
  # (remove! is the mutating one) and the result was discarded, so colons were
  # never actually stripped on save.
  def ensure_not_alpha_code
    self.name = name.to_s.delete(':')
  end
end
