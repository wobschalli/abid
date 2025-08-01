class ChangeLocationDetails < ActiveRecord::Migration[8.0]
  def up
    create_table :locations do |t|
      t.string :name
      t.string :aliases, array: true, default: []
      t.decimal :lon, precision: 15, scale: 10
      t.decimal :lat, precision: 15, scale: 10

      t.timestamps
    end

    change_table :events do |t|
      t.remove :location_lon, :location_lat

      t.references :location, foreign_key: true, null: true
    end

    change_table :users do |t|
      t.remove :lon, :lat

      t.references :location, foreign_key: true, null: true
    end
  end

  def down
    remove_reference :events, :location, null: true, foreign_key: true
    remove_reference :users, :location, null: true, foreign_key: true
    drop_table :locations

    add_column :events, :location_lat, :decimal
    add_column :events, :location_lon, :decimal
    add_column :users, :lat, :decimal
    add_column :users, :lon, :decimal
  end
end
