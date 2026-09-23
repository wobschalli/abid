# What the last "Sync from Discord" actually did.
#
# The button set a flag and the bot acted on it, but nothing came back: a
# coordinator pressed it and got no way to tell a successful sweep that found
# nothing from a message the bot could not reach. Those look identical from the
# board and mean opposite things — one says "the roster is right", the other
# says "stop trusting this page".
#
# Stored rather than derived because the bot is a different process: by the time
# anyone looks at the board, the Report object is long gone.
class AddReconcileNoteToSignupPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :signup_posts, :reconcile_note, :string
    add_column :signup_posts, :reconcile_ok, :boolean
  end
end
