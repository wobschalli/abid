class User < ApplicationRecord
  belongs_to :location
  belongs_to :driver, class_name: 'User', optional: true

  has_many :riders, class_name: 'User', foreign_key: 'driver_id'
  has_and_belongs_to_many :events
  has_and_belongs_to_many :roles

  has_secure_password
end
