class RenameDiscordInfo < ActiveRecord::Migration[8.0]
  def change
    rename_table :discord_info, :discord_infos
  end
end
