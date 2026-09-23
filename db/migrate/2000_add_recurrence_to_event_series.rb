class AddRecurrenceToEventSeries < ActiveRecord::Migration[8.0]
  def change
    change_table :event_series, bulk: true do |t|
      t.date :starts_on                                 # first eligible week; nil = from today
      t.date :ends_on                                   # nil = open ended
      t.integer :interval_weeks, null: false, default: 1 # 1 = weekly, 2 = fortnightly
      # Per-series rather than global: wall-clock times are resolved in this
      # zone, so 9:30 AM stays 9:30 AM across both DST switches.
      t.string :time_zone, null: false, default: 'America/Indiana/Indianapolis'
      t.integer :horizon_weeks, null: false, default: 3  # how far ahead to materialise
      t.date :last_generated_on
    end

    add_index :event_series, [:disabled, :weekday]
  end
end
