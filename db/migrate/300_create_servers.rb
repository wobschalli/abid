class CreateServers < ActiveRecord::Migration[8.0]
  def change
    create_table :servers do |t|
      t.string :name
      t.bigint :discord_id, null: false

      t.unique_constraint :discord_id

      t.timestamps
    end
  end
end
