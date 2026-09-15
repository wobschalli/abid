class AddSourceToRides < ActiveRecord::Migration[8.0]
  def change
    # The ownership boundary. Reaction handling only ever mutates rides it
    # created, so a rider the coordinator added by hand is immune to Discord
    # traffic — including someone un-reacting.
    add_column :rides, :source, :string, null: false, default: 'manual'
    # Set when someone un-reacts after a coordinator already seated them. The
    # seat is freed but the row stays visible rather than silently vanishing.
    add_column :rides, :dropped_at, :datetime

    add_index :rides, [:event_id, :source]
  end
end
