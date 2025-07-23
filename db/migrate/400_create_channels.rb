class CreateChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :channels do |t|
      t.string :name
      t.bigint :discord_id, null: false

      t.unique_constraint :discord_id

      t.references :server, foreign_key: true, null: false

      t.timestamps
    end
  end
end
