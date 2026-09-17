class DropEventsUsers < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO event_signups (event_id, user_id, emoji_id, response_type, created_at, updated_at)
      SELECT DISTINCT
        events_users.event_id,
        events_users.user_id,
        (
          SELECT emojis.id
          FROM emojis
          WHERE emojis.event_id = events_users.event_id
          ORDER BY emojis.id ASC
          LIMIT 1
        ) AS emoji_id,
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM events_users
      WHERE EXISTS (
        SELECT 1
        FROM emojis
        WHERE emojis.event_id = events_users.event_id
      );
    SQL

    drop_table :events_users
  end

  def down
    create_table :events_users, id: false do |t|
      t.references :event
      t.references :user
    end

    execute <<~SQL
      INSERT INTO events_users (event_id, user_id)
      SELECT DISTINCT event_id, user_id
      FROM event_signups;
    SQL
  end
end
