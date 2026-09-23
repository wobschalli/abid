# A name is not an address.
#
# Geocoding searched OpenStreetMap for the location's NAME — "Third and West,
# West Lafayette, Indiana". Four of the apartment complexes never resolved, and
# not because of rate limits or the bounding box: querying them unbounded
# returns zero results too. They are leasing brands, not map features. OSM has
# never heard of "Alight West Lafayette"; it has certainly heard of the street
# it stands on.
#
# Separating the two also fixes the other half. `Map#create_new_location`
# stored a typed pickup ("1838 King Eider Drive") as a location NAME, so a
# one-off pickup spot became a permanent place in the Locations list, named
# after a street address and carrying no zone.
class AddAddressToLocations < ActiveRecord::Migration[8.0]
  def change
    add_column :locations, :address, :string
  end
end
