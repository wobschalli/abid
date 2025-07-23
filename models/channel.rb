class Channel < ApplicationRecord
  belongs_to :server

  has_many :events
end
