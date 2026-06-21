class RideAssignment < ApplicationRecord
  belongs_to :event
  belongs_to :user
  belongs_to :driver, class_name: 'User'

  enum :role, { driver: 0, rider: 1 }

  store :route, accessors: [:waypoints]

  validates :driver_id, :event_id, presence: true
end
