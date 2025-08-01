class AddMessageToEvent < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :message, :string
    add_reference :emojis, :event, null: true #events can now have emojis for reaction farming
  end
end
