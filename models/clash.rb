class Clash < ApplicationRecord
  # "Won't ride with". Symmetric, so rows are stored with the lower user id
  # first and every lookup checks both directions.
  belongs_to :user
  belongs_to :other_user, class_name: 'User'

  before_validation :canonicalize
  validates :user_id, uniqueness: { scope: :other_user_id }
  validate :cannot_clash_with_self

  scope :involving, lambda { |user_id|
    where(user_id: user_id).or(where(other_user_id: user_id))
  }

  def self.between(a, b)
    low, high = [a.to_i, b.to_i].minmax
    find_by(user_id: low, other_user_id: high)
  end

  def self.add(a, b, reason: nil)
    low, high = [a.to_i, b.to_i].minmax
    return nil if low == high
    find_or_create_by(user_id: low, other_user_id: high) { |c| c.reason = reason }
  end

  def self.remove(a, b)
    between(a, b)&.destroy
  end

  # All user ids a given user clashes with.
  def self.ids_for(user_id)
    involving(user_id).pluck(:user_id, :other_user_id).flatten.uniq - [user_id.to_i]
  end

  # { user_id => [other ids] } for a set of users, in one query — the board needs
  # this for every rider on screen and shouldn't do it N times.
  EMPTY = [].freeze

  def self.map_for(user_ids)
    ids = user_ids.map(&:to_i)
    pairs = where(user_id: ids).or(where(other_user_id: ids)).pluck(:user_id, :other_user_id)

    map = pairs.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(a, b), acc|
      acc[a] << b
      acc[b] << a
    end

    # Drop the default_proc so reads on the board don't quietly insert keys.
    map.default_proc = nil
    map.default = EMPTY
    map
  end

  private

  def canonicalize
    return if user_id.nil? || other_user_id.nil?
    self.user_id, self.other_user_id = [user_id, other_user_id].minmax
  end

  def cannot_clash_with_self
    errors.add(:other_user_id, 'cannot clash with self') if user_id == other_user_id
  end
end
