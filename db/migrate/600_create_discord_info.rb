class CreateDiscordInfo < ActiveRecord::Migration[8.0]
  def change
    create_table :discord_info do |t|
      t.string :token, null: false
      t.string :app_id, null: false
      t.string :public_key, null: false
    end
  end
end
