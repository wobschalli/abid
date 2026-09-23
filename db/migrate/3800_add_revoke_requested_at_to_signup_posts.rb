# "I posted that and it was wrong."
#
# A flag the bot polls, not a job queue, and deliberately the same shape as
# reconcile_requested_at: the bot may be down when the button is pressed, and
# this has to survive that.
#
# It exists at all because the web process has no Discord connection and so
# cannot delete the message itself. The tempting alternative — flip the row back
# to draft now and let the bot tidy Discord up later — is the one thing that
# must not happen: with the bot down you would be editing a draft while the
# original was still live in the channel, and pressing Post now would put a
# SECOND message up beside the first. The post stays `posted` until the message
# is really gone.
class AddRevokeRequestedAtToSignupPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :signup_posts, :revoke_requested_at, :datetime
  end
end
