require 'sequel'

Sequel.migration do
  change do
    create_table :users do |t|
      primary_key :id
      String :username, null: false
      String :name
      Integer :grad_year
      String :location

      DateTime :created_at
      DateTime :updated_at
    end
  end
end
