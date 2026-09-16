# Two addresses per person, and a per-event choice of which to use.
#
# Where someone lives and where they are before Friday Abide are often not the
# same place: the census has people living at Lark but standing outside MSEE or
# BHEE when they need collecting, because they come straight from a lab. Sunday
# morning is the opposite — everyone is at home.
#
# So a person has both, and the EVENT decides which one the board and the
# route planner should use. Defaulting to home keeps every existing occurrence
# behaving exactly as it did.
class AddClassLocationAndPickupSource < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :class_location_id, :bigint
    add_index :users, :class_location_id
    add_foreign_key :users, :locations, column: :class_location_id

    # Copied onto each occurrence at generation, like every other series
    # setting, so changing the template does not rewrite history.
    add_column :event_series, :pickup_source, :string, default: 'home', null: false
    add_column :events, :pickup_source, :string, default: 'home', null: false
  end
end
