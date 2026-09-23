# Driver tags — "Friday-Usual", "Sunday-Usual", and whatever else gets invented.
#
# The problem they solve: "Add the regular drivers" meant every active member
# with a seat count, which is the same list on a Friday as on a Sunday. It is
# not the same list in real life. The people who drive after Friday dinner and
# the people who drive to Sunday service overlap but are not the same set, so
# the button either added people who were not coming or was not worth pressing.
#
# A text array on users rather than a Tag model and a join table. The set is
# small, it is edited by one person, and "allow me to make more" then costs
# nothing — typing a tag that does not exist yet creates it. `locations.aliases`
# already works this way. The cost is no rename and no referential integrity;
# for a handful of labels maintained by the coordinator, that is the right
# trade. A GIN index keeps `tags @> ARRAY['Friday-Usual']` fast enough to not
# think about.
#
# driver_tag sits on the SERIES because that is where "this is the Friday one"
# is already recorded, and is copied onto each occurrence the same way
# pickup_source is — so a one-off event can differ from its series, and an
# occurrence keeps working after its series is deleted.
class AddDriverTags < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :tags, :string, array: true, default: [], null: false
    add_index :users, :tags, using: :gin

    add_column :event_series, :driver_tag, :string
    add_column :events, :driver_tag, :string
  end
end
