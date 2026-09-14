class AddRideBoardFields < ActiveRecord::Migration[8.0]
  def change
    # The details rail edits a phone number per person.
    add_column :users, :phone, :string

    # Coarse pickup grouping the board sorts and auto-fills by. Canonical value
    # lives on the location; rides can override it for a single occurrence.
    add_column :locations, :zone, :string
    add_column :rides, :zone, :string

    # Free text the coordinator types ("Eastgate Apts, lot B"). Geocoded into a
    # Location lazily, so the board stays usable when OSM has never heard of the
    # place.
    add_column :rides, :pickup_address, :string

    add_index :locations, :zone
    add_index :rides, :zone

    # "Won't ride with" — a durable fact about two people rather than a
    # per-occurrence one, so it doesn't need re-entering every week.
    create_table :clashes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :other_user, null: false, foreign_key: { to_table: :users }
      t.string :reason

      t.timestamps
    end

    add_index :clashes, [:user_id, :other_user_id], unique: true
  end
end
