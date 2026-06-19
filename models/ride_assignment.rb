class RideAssignment < ApplicationRecord
  belongs_to :event
  belongs_to :driver, class_name: 'User'
  has_and_belongs_to_many :riders, class_name: 'User'

  store :route, accessors: [:waypoints]

  validates :driver_id, :event_id, presence: true
end
