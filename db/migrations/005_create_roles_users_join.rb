require 'sequel'

Sequel.migration do
  change do
    create_join_table(role_id: :roles, user_id: :users)
  end
end
