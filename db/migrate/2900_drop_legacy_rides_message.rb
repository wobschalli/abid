# Removes the second way of announcing rides.
#
# Two mechanisms were running at once. The legacy one — Event.message_due ->
# post_rides_message -> collect_reactions — posted `events.message` off
# `message_rides_at` on the 30-second tick, in parallel with Signup::Publisher.
# They were kept from both landing in the channel by a single clause on
# Event.message_due, which only suppressed the legacy post once a sign-up had
# *already been published*; a sign-up posted late meant two messages.
#
# It was also broken. `post_rides_message` called `event.emojis`, an association
# dropped in 2400_drop_event_emojis, so it raised NoMethodError *after*
# committing rides_message_id — the message went out with no reactions seeded
# and the error was swallowed to stderr.
#
# Nothing here touches a Ride. This deletes a way of asking who needs a lift,
# not any record of who got one.
class DropLegacyRidesMessage < ActiveRecord::Migration[8.0]
  def change
    remove_column :events, :message, :string
    remove_column :events, :message_rides_at, :datetime
    remove_column :events, :collect_rides_at, :datetime
    remove_column :events, :rides_message_id, :bigint
    remove_column :events, :collected_at, :datetime

    remove_column :event_series, :message_lead_hours, :integer, default: 24
    remove_column :event_series, :collect_lead_hours, :integer, default: 2

    # The HABTM the legacy collector wrote into. Ride rows are the real record
    # of who was on an occurrence; this was a parallel, thinner copy.
    drop_table :events_users, id: false do |t|
      t.bigint :event_id
      t.bigint :user_id
      t.index :event_id
      t.index :user_id
    end
  end
end
