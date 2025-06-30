require_relative 'connect'

class Event < Sequel::Model
  many_to_many :users
end
