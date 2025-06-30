require 'sequel'

Sequel.migration do
  change do
    create_join_table(event_id: :events, user_id: :users)
  end
end
