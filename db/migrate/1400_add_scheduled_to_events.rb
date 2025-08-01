class AddScheduledToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :scheduled, :boolean, default: false
  end
end
