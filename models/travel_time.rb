# One directed location pair's driving time, cached permanently.
#
# Permanence is the point, not an optimisation. Fetched fresh each solve, the
# Google matrix costs 60² elements of quota a run — and traffic-aware answers
# drift between runs, so a re-solve wants to move people, which is exactly what
# frozen rides forbid. Fetched once per pair, the numbers are deterministic
# forever and the whole town costs ~900 elements, total, ever.
#
# `source` records whether Google answered or we estimated, so "why is this
# route odd" stays answerable.
class TravelTime < ApplicationRecord
  SOURCES = %w[google estimate].freeze

  belongs_to :from_location, class_name: 'Location'
  belongs_to :to_location, class_name: 'Location'

  validates :seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :source, inclusion: { in: SOURCES }

  scope :from_google, -> { where(source: 'google') }

  # A location that moves invalidates every cached time through it. Wired from
  # Location so nobody has to remember.
  def self.forget!(location_id)
    where(from_location_id: location_id).or(where(to_location_id: location_id)).delete_all
  end
end
