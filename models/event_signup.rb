class EventSignup < ApplicationRecord
  belongs_to :event
  belongs_to :user
  belongs_to :emoji
  enum :response_type, { driver: 0, rider: 1, maybe: 2 }
end
