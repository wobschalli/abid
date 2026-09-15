class CreateAcademicBreaks < ActiveRecord::Migration[8.0]
  def change
    # Shared across every series rather than per-series skip dates: the
    # university calendar is a property of Purdue, not of one Bible study, and
    # nothing should still be generating Sunday occurrences through winter
    # break.
    create_table :academic_breaks do |t|
      t.string :name, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false

      t.timestamps
    end

    add_index :academic_breaks, [:starts_on, :ends_on]

    # users.driver_id: a dead column with a live self-referential foreign key
    # and index. It meant "this person's permanent driver", which was always
    # wrong — driving is per-occurrence and lives on rides.driver_ride_id now.
    # Nothing has read or written it since that change.
    remove_column :users, :driver_id, :bigint
  end
end
