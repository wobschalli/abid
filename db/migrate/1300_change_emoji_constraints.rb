class ChangeEmojiConstraints < ActiveRecord::Migration[8.0]
  def up
    change_table :emojis do |t|
      t.remove :discord_id
      t.remove :server_id

      t.bigint :discord_id, null: true
      t.references :server, null: true, foreign_key: true
    end
  end

  def down
  end
end
