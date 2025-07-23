class CreateEmojis < ActiveRecord::Migration[8.0]
  def change
    create_table :emojis do |t|
      t.string :name
      t.bigint :discord_id, null: false

      t.unique_constraint :discord_id

      t.references :server, null: false, foreign_key: true

      t.timestamps
    end

  end
end
