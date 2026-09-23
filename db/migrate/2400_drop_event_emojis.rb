class DropEventEmojis < ActiveRecord::Migration[8.0]
  # `Event has_many :emojis` over a single emojis.event_id column was a
  # one-to-many modelling a many-to-many: assigning an emoji to event B silently
  # stole it from event A, so two events could never offer the same emoji. That
  # is fatal for sign-up posts, where 1️⃣ means a different ride every week.
  #
  # Emoji identity now lives inline on signup_options. The emojis table reverts
  # to what Bot::Setup#setup_emojis actually populates: a catalogue of the
  # server's custom emoji, one row per Discord emoji id.
  def up
    remove_column :emojis, :event_id

    # Unicode placeholder rows only ever existed because the old /event create
    # modal made them. Nothing reads them now.
    execute 'DELETE FROM emojis WHERE discord_id IS NULL'

    change_column_null :emojis, :discord_id, false
    # Migration 1300 dropped this, so setup_emojis' find_or_create_by could
    # duplicate on a restart race.
    add_index :emojis, :discord_id, unique: true
  end

  def down
    remove_index :emojis, column: :discord_id
    change_column_null :emojis, :discord_id, true
    add_reference :emojis, :event
  end
end
