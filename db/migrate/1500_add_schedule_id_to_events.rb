class AddScheduleIdToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :send_schedule_id, :string
    add_column :events, :collect_schedule_id, :string
  end
end
