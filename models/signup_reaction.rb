class SignupReaction < ApplicationRecord
  # One person's reaction to one option, and the ride it produced.
  #
  # Without this table you cannot tell a coordinator-added rider from a
  # reaction-added one, cannot tell whether a ride is still backed by a live
  # reaction, and cannot tell whether someone un-reacted from *this* option or
  # from a different one pointing at the same occurrence.
  belongs_to :signup_option
  belongs_to :user, optional: true
  belongs_to :ride, optional: true

  has_one :event, through: :signup_option

  validates :discord_user_id, presence: true,
                              uniqueness: { scope: :signup_option_id }

  scope :live, -> { where(removed_at: nil) }
  scope :removed, -> { where.not(removed_at: nil) }

  def live?
    removed_at.nil?
  end
end
