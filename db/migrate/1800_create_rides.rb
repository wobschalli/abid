class CreateRides < ActiveRecord::Migration[8.0]
  def change
    create_table :rides do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: 'rider'
      t.string :status, null: false, default: 'requested'
      t.integer :seats
      t.references :pickup_location, foreign_key: { to_table: :locations }
      t.references :driver_ride, foreign_key: { to_table: :rides }
      t.string :note
      t.datetime :signed_up_at

      t.timestamps
    end

    # One row per person per occurrence.
    add_index :rides, [:event_id, :user_id], unique: true
    add_index :rides, [:event_id, :role]
  end
end
