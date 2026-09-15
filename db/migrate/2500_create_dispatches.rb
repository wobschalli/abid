class CreateDispatches < ActiveRecord::Migration[8.0]
  def change
    # One row per press of "Send to drivers". Doubles as the outbox the bot
    # polls: the web process writes status 'queued', the bot claims it.
    create_table :dispatches do |t|
      t.references :event, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'queued' # queued sending sent partial failed
      t.string :scope, null: false, default: 'changed' # changed all
      t.integer :attempt, null: false, default: 1
      t.jsonb :board_snapshot, null: false, default: {}
      t.datetime :requested_at, null: false
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :dispatches, [:event_id, :attempt], unique: true
    add_index :dispatches, [:status, :requested_at]

    # One row per driver per dispatch. Denormalised on purpose — rides get
    # deleted, and the log has to outlive the rows it describes.
    create_table :dispatch_messages do |t|
      t.references :dispatch, null: false, foreign_key: true
      t.references :driver_ride, foreign_key: { to_table: :rides, on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.bigint :discord_id, null: false
      t.string :driver_name, null: false
      t.string :status, null: false, default: 'pending' # pending sent failed skipped
      t.text :body
      t.string :route_url
      t.jsonb :roster, null: false, default: {}
      t.string :roster_digest, null: false
      t.bigint :discord_message_id
      t.string :error_class
      t.text :error_message
      t.datetime :sent_at
      t.integer :attempts, null: false, default: 0

      t.timestamps
    end

    add_index :dispatch_messages, [:dispatch_id, :driver_ride_id], unique: true
    add_index :dispatch_messages, [:driver_ride_id, :status]
  end
end
