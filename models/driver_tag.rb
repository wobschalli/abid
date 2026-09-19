# The name of a driver tag — "Friday-Usual", "Van-Driver", whatever gets
# invented next.
#
# Holds only the name. Who carries it is users.tags, because that is what every
# board lookup actually asks and an array answers it without a join.
class DriverTag < ApplicationRecord
  validates :name, presence: true
  validate :name_must_be_unique_ignoring_case

  scope :by_name, -> { order(Arel.sql('lower(name)')) }

  before_validation { self.name = User.canonical_tag(name) }

  # Creating a tag that already exists is not an error — somebody wanted that
  # tag to exist and it does.
  def self.register(name)
    canonical = User.canonical_tag(name)
    return nil if canonical.blank?

    find_by('lower(name) = ?', canonical.downcase) || create(name: canonical)
  end

  # Removing the name also takes it off everyone carrying it. The alternative
  # is a tag that is gone from every list but still quietly scoping a board.
  def retire!
    transaction do
      User.tagged(name).find_each do |user|
        user.update!(tags: user.tags.reject { |t| t.casecmp?(name) })
      end
      destroy
    end
  end

  private

  def name_must_be_unique_ignoring_case
    return if name.blank?

    clash = self.class.where('lower(name) = ?', name.downcase).where.not(id: id).exists?
    errors.add(:name, 'already exists') if clash
  end
end
