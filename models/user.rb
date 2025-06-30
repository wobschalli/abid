require_relative 'connect'

class User < Sequel::Model
  many_to_many :events
  many_to_many :roles
end
