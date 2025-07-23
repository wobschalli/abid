class Event < ApplicationRecord
  belongs_to :channel
  belongs_to :driver, class_name: 'User', optional: true
  belongs_to :location

  has_many :riders, class_name: 'User', foreign_key: 'driver_id'
  has_and_belongs_to_many :users

  def disable
    self.disabled = true
    self.save
  end

  def enable
    self.disabled = false
    self.save
  end

  def to_s
    "#{name} at [#{location}] from #{start_time&.strftime('%Y-%m-%d %H:%M')} until #{start_time&.strftime('%Y-%m-%d %H:%M')}"
  end
end
