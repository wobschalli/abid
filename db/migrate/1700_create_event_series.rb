class CreateEventSeries < ActiveRecord::Migration[8.0]
  def change
    create_table :event_series do |t|
      t.string :name, null: false
      t.string :section
      t.integer :weekday
      t.time :start_time_of_day
      t.time :end_time_of_day
      t.integer :message_lead_hours, default: 24
      t.integer :collect_lead_hours, default: 2
      t.string :message
      t.boolean :disabled, default: false, null: false
      t.references :channel, foreign_key: true
      t.references :location, foreign_key: true

      t.timestamps
    end

    add_reference :events, :series, foreign_key: { to_table: :event_series }
    add_column :events, :section, :string
    add_column :events, :collected_at, :datetime

    add_index :events, [:series_id, :start_time], unique: true
  end
end
