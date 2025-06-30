require 'sequel'

Sequel.migration do
  change do
    alter_table :events do
      drop_column :channel

      add_column :date, DateTime
      add_column :message_rides, DateTime
      add_column :collect_rides, DateTime
      add_column :message_id, Integer
    end
  end
end
