require 'sequel'

Sequel.migration do
  change do
    alter_table :users do
      add_column :discord_id, Integer
    end
  end
end
