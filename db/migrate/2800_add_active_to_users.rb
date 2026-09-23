# Who is actually part of the fellowship this year.
#
# The Discord sync brings in everyone who has ever joined the server — 271
# people, including alumni, visitors and bots' worth of one-time joiners. The
# census is the list of people who said "I am here this year", and that is a
# much more useful roster for a rides coordinator than "everyone Discord knows
# about".
#
# Default false: nobody is active until something says so, either the census
# import or a coordinator pressing the toggle. Defaulting true would quietly
# declare all 271 active and make the distinction meaningless on day one.
class AddActiveToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :active, :boolean, default: false, null: false
    add_index :users, :active
  end
end
