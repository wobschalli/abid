class RemoveDisabledFromEvents < ActiveRecord::Migration[8.0]
  def change
    remove_column :events, :disabled, :boolean
  end
end