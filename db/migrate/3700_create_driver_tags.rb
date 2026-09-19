# A registry of tag names, so a tag can exist before anybody carries it.
#
# Membership still lives in users.tags — that is the thing every lookup asks
# about, and an array with a GIN index answers it in one hop. This table only
# holds NAMES, which is the piece the array cannot: derive the list of tags
# from the people who have them and a tag with no members is indistinguishable
# from a tag that was never created. You could not make one in advance, and
# deleting the last member silently deleted the tag.
#
# So: create here, apply there. `known_tags` unions this with what people
# actually carry and what the schedule asks for, which keeps tags created
# before this table existed working.
class CreateDriverTags < ActiveRecord::Migration[8.0]
  def change
    create_table :driver_tags do |t|
      t.string :name, null: false
      t.timestamps
    end

    # Case-insensitive, because "friday-usual" and "Friday-Usual" are the same
    # tag to everyone except a database.
    add_index :driver_tags, 'lower(name)', unique: true, name: 'index_driver_tags_on_lower_name'
  end
end
