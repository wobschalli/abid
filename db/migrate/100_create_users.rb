class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name
      t.string :username
      t.bigint :discord_id, null: false
      t.integer :grad_year
      t.integer :lat
      t.integer :lon
      t.integer :capacity
      t.boolean :leader, default: false

      t.belongs_to :driver, foreign_key: { to_table: :users }, null: true

      t.unique_constraint :discord_id

      t.timestamps
    end
  end
end
