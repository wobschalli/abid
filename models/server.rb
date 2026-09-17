class Server < ApplicationRecord
  has_many :channels, dependent: :destroy
  has_many :emojis, dependent: :destroy
  has_many :events, through: :channels
end
