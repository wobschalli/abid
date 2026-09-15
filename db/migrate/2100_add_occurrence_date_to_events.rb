class AddOccurrenceDateToEvents < ActiveRecord::Migration[8.0]
  # The dedupe key for a series occurrence was [series_id, start_time]. That is
  # wrong across a DST boundary: the same wall clock is a different UTC instant
  # in March than in November, so `find_by(start_time:)` misses and you get a
  # duplicate occurrence — and therefore a second rides message. The local
  # calendar date is the stable identity of "this week's service".
  def up
    add_column :events, :occurrence_date, :date

    execute <<~SQL
      UPDATE events
         SET occurrence_date = (start_time AT TIME ZONE 'UTC'
                                           AT TIME ZONE 'America/Indiana/Indianapolis')::date
       WHERE start_time IS NOT NULL
    SQL

    remove_index :events, column: [:series_id, :start_time]
    # NULLs are distinct in Postgres, so this constrains series occurrences only
    # — a one-off retreat stays unconstrained, which is correct.
    add_index :events, [:series_id, :occurrence_date], unique: true
    add_index :events, :occurrence_date

    # Event.active is `where(disabled: false)`, which silently drops NULL rows.
    execute 'UPDATE events SET disabled = false WHERE disabled IS NULL'
    change_column_default :events, :disabled, false
    change_column_null :events, :disabled, false
  end

  def down
    change_column_null :events, :disabled, true
    remove_index :events, column: :occurrence_date
    remove_index :events, column: [:series_id, :occurrence_date]
    add_index :events, [:series_id, :start_time], unique: true
    remove_column :events, :occurrence_date
  end
end
