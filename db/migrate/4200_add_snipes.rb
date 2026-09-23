# "Don't snipe me."
#
# A snipe is a photo of someone spotted on campus, posted to a channel and
# @mentioning them. Most people enjoy it; some do not, and until now there was
# no way to say so. The preference lives on the user (default: fine with it —
# that is how the channel has always worked), and the bot removes snipes of
# people who have opted out.
#
# The channel itself gets a `purpose` rather than being found by name:
# Bot::Setup#setup_channels rewrites `name` from Discord on every boot, so a
# rename in Discord would silently switch enforcement off. One channel per
# purpose, enforced by the partial unique index.
#
# notice_message_id remembers the posted opt-out message so it is posted once
# and refreshed in place thereafter; notice_requested_at is the outbox flag the
# rake task sets and the bot's tick consumes, the same shape as
# signup_posts.reconcile_requested_at.
class AddSnipes < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :snipes_opt_out, :boolean, null: false, default: false
    add_column :users, :snipes_preference_at, :datetime
    add_index :users, :snipes_opt_out, where: 'snipes_opt_out'

    add_column :channels, :purpose, :string
    add_index :channels, :purpose, unique: true, where: 'purpose IS NOT NULL'
    add_column :channels, :notice_message_id, :bigint
    add_column :channels, :notice_requested_at, :datetime
  end
end
