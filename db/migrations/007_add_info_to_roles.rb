require 'sequel'

Sequel.migration do
  change do
    alter_table :roles do
      add_column :discord_id, Integer
      add_column :admin, :boolean
    end
  end
end
