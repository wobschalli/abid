class Server < ApplicationRecord
  has_many :channels
  has_many :emojis
  has_many :events, through: :channels
end
