class DropEventsUsers < ActiveRecord::Migration[8.0]
  def up
    drop_table :events_users
  end
  def down
    create_table :events_users, id: false do |t|
      t.references :event
      t.references :user
    end
  end
end
