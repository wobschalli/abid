# "Got it" on a driver's DM.
#
# Discord exposes no read state to a bot — there is no event and no field, and
# their own client never surfaces it. Delivery we already know: a DispatchMessage
# is `sent` or `failed` with the real error, so a bounced DM (50007, closed DMs)
# is already visible. What was missing is the half that matters on a Sunday
# morning: did the driver actually take it in.
#
# A tap is a better answer than a read receipt would have been. A read receipt
# means a notification was opened, possibly on a lock screen by someone who then
# forgot. This is deliberate.
class AddAcknowledgedAtToDispatchMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :dispatch_messages, :acknowledged_at, :datetime
  end
end
