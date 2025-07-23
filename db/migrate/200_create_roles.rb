class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name
      t.bigint :discord_id, null: false
      t.boolean :admin, default: false

      t.unique_constraint :discord_id

      t.timestamps
    end

    create_table :roles_users, id: false do |t|
      t.belongs_to :role
      t.belongs_to :user
    end
  end
end
