class RevampEventSystem < ActiveRecord::Migration[8.0]
  class Event < ActiveRecord::Base; end
  def change
    create_table :event_signups do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :emoji, null: false, foreign_key: true
      t.integer :response_type, null: false, default: 0
      t.timestamps
    end
    create_table :ride_assignments do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true # rider
      t.references :driver, null: false, foreign_key: { to_table: :users }
      t.integer :role, null: false, default: 1
      t.jsonb :route, default: {}
      t.timestamps
    end
    add_reference :events, :organizer, foreign_key: { to_table: :users }
    add_column :events, :status, :integer, default: 0
    backfill_status_for_events
  end
  def backfill_status_for_events
    Event.reset_column_information
    # disabled column migrated to status enum:
    #   disabled=true  → status=4 (cancelled)
    #   disabled=false, scheduled=true  → status=1 (scheduled)
    #   disabled=false, scheduled=false → status=0 (draft)
  end
end
