# The two pieces of state the time-optimal auto-fill needs.
#
# rides.pickup_position: the order the optimizer chose within one car. Nullable
# on purpose — a board the optimizer has never touched keeps RoutePlanner's
# deterministic zone-then-name order, so nothing changes until someone presses
# Auto-fill. Deliberately NOT part of DispatchDigest: the digest treats riders
# as a set, so re-ordering a sent car's pickups never re-flags its driver.
#
# travel_times: one row per directed location pair, fetched from the Google
# Distance Matrix once and kept. Cached permanently rather than per-solve
# because the alternative fights every requirement at once: 60 points is 3,600
# elements of quota per solve, and traffic-aware answers change between runs —
# a re-solve that gets different numbers wants to move people, which is exactly
# what frozen rides forbid. ~30 locations in real use is at most ~900 pairs,
# fetched once, then free and deterministic forever.
#
# `source` says whether a row came from Google or from the haversine estimate,
# so "why is this route weird" is answerable later.
class AddOptimizerTables < ActiveRecord::Migration[8.0]
  def change
    add_column :rides, :pickup_position, :integer

    create_table :travel_times do |t|
      t.references :from_location, null: false, foreign_key: { to_table: :locations }
      t.references :to_location, null: false, foreign_key: { to_table: :locations }
      t.integer :seconds, null: false
      t.string :source, null: false, default: 'estimate'
      t.timestamps
    end

    add_index :travel_times, %i[from_location_id to_location_id], unique: true
  end
end
