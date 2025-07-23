class CreateScheduleSwitch < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :disabled, :boolean, default: false
  end
end
