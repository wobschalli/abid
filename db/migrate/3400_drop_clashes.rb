# "Won't ride with", removed.
#
# The mechanism was a user-to-user pair that blocked auto-fill from seating two
# people together and turned a shared car red on the board. It is going because
# it asked a coordinator to record something about two people's relationship in
# a rides app, and because the real cases it was reaching for — "these two have
# a thing after", "she gets carsick in the back" — are what the per-ride note
# field is for, in words, without a permanent record of who cannot stand whom.
#
# Auto-fill only ever filled empty seats and never moved anyone, so removing the
# constraint cannot strand a rider: the worst case is a pairing a human then
# drags apart, which was always the fallback anyway.
#
# Irreversible on purpose. `down` could recreate the table but not the pairs,
# and a silently empty "won't ride with" list is worse than none at all — it
# would read as "nobody has a conflict" rather than "this data is gone".
class DropClashes < ActiveRecord::Migration[8.0]
  def up
    drop_table :clashes
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'the clash pairs themselves are not recoverable'
  end
end
