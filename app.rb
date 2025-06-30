require_relative 'map'

class App < Sinatra::Base
  helpers Phlex::Sinatra

  def initialize
    @db = Sequel.sqlite File.join(Dir.pwd, 'db', 'abid.sqlite')
    # create_users_and_roles
  end

  get '/' do
    phlex Root.new
  end

  private
  def create_users_and_roles
    users = BOT.get_all_users CONFIG['servers.test']
    users.each do |user|
      User.find_or_create(discord_id: user.id) do |u|
        u.username = user.username
        u.name = user.name
        u.roles = user.roles.map do |role|
          Role.find_or_create(discord_id: role.id) do |r|
            r.name = role.name
            r.admin = role.administrator
          end
        end
      end
    end
  end
end
