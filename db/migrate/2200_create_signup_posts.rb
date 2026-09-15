class CreateSignupPosts < ActiveRecord::Migration[8.0]
  def change
    # A sign-up message the bot composes and posts to Discord at a time the
    # coordinator chooses, then watches the reactions on.
    #
    # Because the bot does the sending, posting twice is possible and would be
    # irreversible — hence the status machine, publish_attempts, and
    # rendered_body, which together let a crash mid-send be recovered rather
    # than repeated into a channel of eighty people.
    create_table :signup_posts do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.date :service_date
      t.text :intro
      t.text :outro

      # draft -> scheduled -> posting -> posted -> closed, plus failed
      t.string :status, null: false, default: 'draft'
      t.datetime :post_at                 # when the bot should send it
      t.bigint :discord_message_id        # null until sent
      t.text :rendered_body               # written BEFORE sending, for recovery
      t.integer :publish_attempts, null: false, default: 0
      t.string :last_error

      t.datetime :posted_at
      t.datetime :closed_at
      t.datetime :reconciled_at
      t.datetime :reconcile_requested_at

      t.timestamps
    end

    add_index :signup_posts, :discord_message_id, unique: true
    add_index :signup_posts, [:status, :post_at]
    add_index :signup_posts, [:status, :service_date]

    create_table :signup_options do |t|
      t.references :signup_post, null: false, foreign_key: true
      # Which occurrence this emoji books. Required in practice — the composer
      # will not let you schedule a post with an unbound option — but nullable
      # so a half-built draft can be saved.
      t.references :event, foreign_key: true
      t.string :label
      t.integer :position, null: false, default: 0

      # Canonical match key, normalised through TanukiEmoji: "u:one" for unicode,
      # "c:1039284756000" for a server emoji. One indexed equality check on the
      # gateway hot path rather than an OR across a nullable id and a name.
      t.string :emoji_key, null: false
      t.string :emoji_unicode
      t.string :emoji_name
      t.bigint :emoji_discord_id
      t.boolean :emoji_animated, null: false, default: false

      # Denormalised from the parent so a reaction lookup is one index hit with
      # no join. Written when the post is sent; the reconciler re-asserts it.
      t.bigint :discord_message_id
      t.datetime :synced_at

      t.timestamps
    end

    add_index :signup_options, [:signup_post_id, :emoji_key], unique: true
    add_index :signup_options, [:signup_post_id, :position]
    add_index :signup_options, [:discord_message_id, :emoji_key],
              unique: true,
              where: 'discord_message_id IS NOT NULL',
              name: 'index_signup_options_on_message_and_emoji'

    # Which reaction produced which ride. `rides` is unique on
    # [event_id, user_id] and carries no provenance, so without this we cannot
    # answer "is this ride still backed by a live reaction" or "did they
    # un-react from THIS option or another one pointing at the same event".
    create_table :signup_reactions do |t|
      t.references :signup_option, null: false, foreign_key: true
      t.bigint :discord_user_id, null: false
      t.references :user, foreign_key: true
      t.references :ride, foreign_key: true
      t.datetime :reacted_at, null: false
      t.datetime :removed_at
      t.string :source, null: false, default: 'gateway' # gateway | reconcile

      t.timestamps
    end

    add_index :signup_reactions, [:signup_option_id, :discord_user_id], unique: true
    add_index :signup_reactions, [:signup_option_id, :removed_at]
  end
end
