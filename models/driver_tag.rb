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

  # Delete the name AND every reference to it.
  #
  # Three places refer to a tag, and `known_tags` unions all three so that a tag
  # from before this table existed is still manageable. That union is also why
  # deleting the row alone does not work: the series still said "Friday-Usual",
  # so the next page load re-registered it and the tag came back from the dead.
  # Friday-Usual and Sunday-Usual were the only two tags a series pointed at,
  # which is exactly why those two were the ones that would not delete.
  #
  # Clearing the series is the honest consequence: the tag does not exist, so
  # nothing can be scoped to it. That board goes back to offering every driver
  # until a new tag is set on the series.
  def retire!
    transaction do
      User.tagged(name).find_each do |user|
        user.update!(tags: user.tags.reject { |t| t.casecmp?(name) })
      end

      EventSeries.where('lower(driver_tag) = ?', name.downcase).update_all(driver_tag: nil)
      Event.where('lower(driver_tag) = ?', name.downcase).update_all(driver_tag: nil)

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
