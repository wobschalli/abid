require 'sequel'

Sequel.migration do
  change do
    create_table :events do
      primary_key :id
      Integer :channel


      DateTime :created_at
      DateTime :updated_at
    end
  end
end
