class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string :name
      t.integer :location_lon
      t.integer :location_lat
      t.bigint :rides_message_id
      t.datetime :start_time
      t.datetime :end_time
      t.datetime :message_rides_at
      t.datetime :collect_rides_at

      t.unique_constraint :rides_message_id

      t.references :channel, foreign_key: true, null: true

      t.timestamps
    end

    create_table :events_users, id: false do |t|
      t.belongs_to :event
      t.belongs_to :user
    end
  end
end
