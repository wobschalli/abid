# A place is either verified against a real address or it is a guess, and the
# difference has to be visible. Until now every pin looked equally
# authoritative — an eyeballed seed coordinate, a Nominatim hit on the wrong
# road, and a rooftop match on the actual building all rendered as the same
# dot, and drivers were sent to the dot.
#
# place_id is Google's stable identifier for the resolved place, which makes
# re-verification idempotent and lets a later run tell "same building, better
# coordinates" from "a different building entirely".
#
# The two answer columns on users keep the member's own words — "Either BHEE
# or 3rd and West because of lab" — so that when the resolver refuses to
# guess, the coordinator sees what was actually written instead of a blank.
class AddVerificationToLocations < ActiveRecord::Migration[8.0]
  def change
    add_column :locations, :place_id, :string
    add_column :locations, :verification, :string, null: false, default: 'unverified'
    add_column :locations, :verified_at, :datetime
    add_index :locations, :verification

    add_column :users, :residence_answer, :string
    add_column :users, :friday_answer, :string
  end
end
