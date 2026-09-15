# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2400) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "channels", force: :cascade do |t|
    t.string "name"
    t.bigint "discord_id", null: false
    t.bigint "server_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["server_id"], name: "index_channels_on_server_id"
    t.unique_constraint ["discord_id"]
  end

  create_table "clashes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "other_user_id", null: false
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["other_user_id"], name: "index_clashes_on_other_user_id"
    t.index ["user_id", "other_user_id"], name: "index_clashes_on_user_id_and_other_user_id", unique: true
    t.index ["user_id"], name: "index_clashes_on_user_id"
  end

  create_table "discord_infos", force: :cascade do |t|
    t.string "token", null: false
    t.string "app_id", null: false
    t.string "public_key", null: false
  end

  create_table "emojis", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "discord_id", null: false
    t.bigint "server_id"
    t.index ["discord_id"], name: "index_emojis_on_discord_id", unique: true
    t.index ["server_id"], name: "index_emojis_on_server_id"
  end

  create_table "event_series", force: :cascade do |t|
    t.string "name", null: false
    t.string "section"
    t.integer "weekday"
    t.time "start_time_of_day"
    t.time "end_time_of_day"
    t.integer "message_lead_hours", default: 24
    t.integer "collect_lead_hours", default: 2
    t.string "message"
    t.boolean "disabled", default: false, null: false
    t.bigint "channel_id"
    t.bigint "location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "starts_on"
    t.date "ends_on"
    t.integer "interval_weeks", default: 1, null: false
    t.string "time_zone", default: "America/Indiana/Indianapolis", null: false
    t.integer "horizon_weeks", default: 3, null: false
    t.date "last_generated_on"
    t.index ["channel_id"], name: "index_event_series_on_channel_id"
    t.index ["disabled", "weekday"], name: "index_event_series_on_disabled_and_weekday"
    t.index ["location_id"], name: "index_event_series_on_location_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.bigint "rides_message_id"
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "message_rides_at"
    t.datetime "collect_rides_at"
    t.bigint "channel_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "disabled", default: false, null: false
    t.bigint "location_id"
    t.string "repeats_every"
    t.string "message"
    t.boolean "scheduled", default: false
    t.string "send_schedule_id"
    t.string "collect_schedule_id"
    t.bigint "series_id"
    t.string "section"
    t.datetime "collected_at"
    t.date "occurrence_date"
    t.index ["channel_id"], name: "index_events_on_channel_id"
    t.index ["location_id"], name: "index_events_on_location_id"
    t.index ["occurrence_date"], name: "index_events_on_occurrence_date"
    t.index ["series_id", "occurrence_date"], name: "index_events_on_series_id_and_occurrence_date", unique: true
    t.index ["series_id"], name: "index_events_on_series_id"
    t.unique_constraint ["rides_message_id"]
  end

  create_table "events_users", id: false, force: :cascade do |t|
    t.bigint "event_id"
    t.bigint "user_id"
    t.index ["event_id"], name: "index_events_users_on_event_id"
    t.index ["user_id"], name: "index_events_users_on_user_id"
  end

  create_table "locations", force: :cascade do |t|
    t.string "name"
    t.string "aliases", default: [], array: true
    t.decimal "lon", precision: 15, scale: 10
    t.decimal "lat", precision: 15, scale: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "zone"
    t.index ["zone"], name: "index_locations_on_zone"
  end

  create_table "rides", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "rider", null: false
    t.string "status", default: "requested", null: false
    t.integer "seats"
    t.bigint "pickup_location_id"
    t.bigint "driver_ride_id"
    t.string "note"
    t.datetime "signed_up_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "zone"
    t.string "pickup_address"
    t.string "source", default: "manual", null: false
    t.datetime "dropped_at"
    t.index ["driver_ride_id"], name: "index_rides_on_driver_ride_id"
    t.index ["event_id", "role"], name: "index_rides_on_event_id_and_role"
    t.index ["event_id", "source"], name: "index_rides_on_event_id_and_source"
    t.index ["event_id", "user_id"], name: "index_rides_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_rides_on_event_id"
    t.index ["pickup_location_id"], name: "index_rides_on_pickup_location_id"
    t.index ["user_id"], name: "index_rides_on_user_id"
    t.index ["zone"], name: "index_rides_on_zone"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.bigint "discord_id", null: false
    t.boolean "admin", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.unique_constraint ["discord_id"]
  end

  create_table "roles_users", id: false, force: :cascade do |t|
    t.bigint "role_id"
    t.bigint "user_id"
    t.index ["role_id"], name: "index_roles_users_on_role_id"
    t.index ["user_id"], name: "index_roles_users_on_user_id"
  end

  create_table "servers", force: :cascade do |t|
    t.string "name"
    t.bigint "discord_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false

    t.unique_constraint ["discord_id"]
  end

  create_table "signup_options", force: :cascade do |t|
    t.bigint "signup_post_id", null: false
    t.bigint "event_id"
    t.string "label"
    t.integer "position", default: 0, null: false
    t.string "emoji_key", null: false
    t.string "emoji_unicode"
    t.string "emoji_name"
    t.bigint "emoji_discord_id"
    t.boolean "emoji_animated", default: false, null: false
    t.bigint "discord_message_id"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discord_message_id", "emoji_key"], name: "index_signup_options_on_message_and_emoji", unique: true, where: "(discord_message_id IS NOT NULL)"
    t.index ["event_id"], name: "index_signup_options_on_event_id"
    t.index ["signup_post_id", "emoji_key"], name: "index_signup_options_on_signup_post_id_and_emoji_key", unique: true
    t.index ["signup_post_id", "position"], name: "index_signup_options_on_signup_post_id_and_position"
    t.index ["signup_post_id"], name: "index_signup_options_on_signup_post_id"
  end

  create_table "signup_posts", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "created_by_id"
    t.date "service_date"
    t.text "intro"
    t.text "outro"
    t.string "status", default: "draft", null: false
    t.datetime "post_at"
    t.bigint "discord_message_id"
    t.text "rendered_body"
    t.integer "publish_attempts", default: 0, null: false
    t.string "last_error"
    t.datetime "posted_at"
    t.datetime "closed_at"
    t.datetime "reconciled_at"
    t.datetime "reconcile_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_signup_posts_on_channel_id"
    t.index ["created_by_id"], name: "index_signup_posts_on_created_by_id"
    t.index ["discord_message_id"], name: "index_signup_posts_on_discord_message_id", unique: true
    t.index ["status", "post_at"], name: "index_signup_posts_on_status_and_post_at"
    t.index ["status", "service_date"], name: "index_signup_posts_on_status_and_service_date"
  end

  create_table "signup_reactions", force: :cascade do |t|
    t.bigint "signup_option_id", null: false
    t.bigint "discord_user_id", null: false
    t.bigint "user_id"
    t.bigint "ride_id"
    t.datetime "reacted_at", null: false
    t.datetime "removed_at"
    t.string "source", default: "gateway", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ride_id"], name: "index_signup_reactions_on_ride_id"
    t.index ["signup_option_id", "discord_user_id"], name: "index_signup_reactions_on_signup_option_id_and_discord_user_id", unique: true
    t.index ["signup_option_id", "removed_at"], name: "index_signup_reactions_on_signup_option_id_and_removed_at"
    t.index ["signup_option_id"], name: "index_signup_reactions_on_signup_option_id"
    t.index ["user_id"], name: "index_signup_reactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "username"
    t.bigint "discord_id", null: false
    t.integer "grad_year"
    t.integer "capacity"
    t.boolean "leader", default: false
    t.bigint "driver_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "location_id"
    t.string "password_digest"
    t.string "phone"
    t.index ["driver_id"], name: "index_users_on_driver_id"
    t.index ["location_id"], name: "index_users_on_location_id"
    t.unique_constraint ["discord_id"]
  end

  add_foreign_key "channels", "servers"
  add_foreign_key "clashes", "users"
  add_foreign_key "clashes", "users", column: "other_user_id"
  add_foreign_key "emojis", "servers"
  add_foreign_key "event_series", "channels"
  add_foreign_key "event_series", "locations"
  add_foreign_key "events", "channels"
  add_foreign_key "events", "event_series", column: "series_id"
  add_foreign_key "events", "locations"
  add_foreign_key "rides", "events"
  add_foreign_key "rides", "locations", column: "pickup_location_id"
  add_foreign_key "rides", "rides", column: "driver_ride_id"
  add_foreign_key "rides", "users"
  add_foreign_key "signup_options", "events"
  add_foreign_key "signup_options", "signup_posts"
  add_foreign_key "signup_posts", "channels"
  add_foreign_key "signup_posts", "users", column: "created_by_id"
  add_foreign_key "signup_reactions", "rides"
  add_foreign_key "signup_reactions", "signup_options"
  add_foreign_key "signup_reactions", "users"
  add_foreign_key "users", "locations"
  add_foreign_key "users", "users", column: "driver_id"
end
