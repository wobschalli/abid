class User < ApplicationRecord
  belongs_to :location
  belongs_to :driver, class_name: 'User', optional: true

  has_many :riders, class_name: 'User', foreign_key: 'driver_id'
  has_many :event_signups, dependent: :destroy
  has_many :events, through: :event_signups
  has_and_belongs_to_many :roles

  has_secure_password

  scope :drivers, -> { joins(:roles).where(roles: { name: "Drivers" }) }
  scope :riders, -> { joins(:roles).where(roles: {name: "Riders" }) }

  def driver?
    roles.exists(name: "Drivers")
  end

  def rider?
    roles.exists(name: "Riders")
  end

  def coordinator?
    roles.exists(name: "Coordinator")
  end
end
