class ChangeLocationDetails < ActiveRecord::Migration[8.0]
  def change
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
end
