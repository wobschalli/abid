class Emoji < ApplicationRecord
  belongs_to :server
  belongs_to :event, optional: true

  before_save :ensure_not_alpha_code

  scope :find_by_codepoints, ->(codepoints) { where(name: TanukiEmoji.find_by_codepoints(codepoints)&.name) }

  def alpha_code
    ":#{self.name}:"
  end

  def codepoints
    TanukiEmoji.find_by_alpha_code(alpha_code)&.codepoints
  end

  def modal_display
    codepoints || alpha_code
  end

  def to_reaction #use as a reaction in Discordrb::Message#react
    codepoints || "#{name}:#{discord_id}"
  end

  private
  # `self.name.remove ':'` was a silent no-op: String#remove is non-mutating
  # (remove! is the mutating one) and the result was discarded, so colons were
  # never actually stripped on save.
  def ensure_not_alpha_code
    self.name = name.to_s.delete(':')
  end
end
