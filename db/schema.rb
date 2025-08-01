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

ActiveRecord::Schema[8.0].define(version: 1500) do
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

  create_table "discord_infos", force: :cascade do |t|
    t.string "token", null: false
    t.string "app_id", null: false
    t.string "public_key", null: false
  end

  create_table "emojis", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "event_id"
    t.bigint "discord_id"
    t.bigint "server_id"
    t.index ["event_id"], name: "index_emojis_on_event_id"
    t.index ["server_id"], name: "index_emojis_on_server_id"
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
    t.boolean "disabled", default: false
    t.bigint "location_id"
    t.string "repeats_every"
    t.string "message"
    t.boolean "scheduled", default: false
    t.string "send_schedule_id"
    t.string "collect_schedule_id"
    t.index ["channel_id"], name: "index_events_on_channel_id"
    t.index ["location_id"], name: "index_events_on_location_id"
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
    t.index ["driver_id"], name: "index_users_on_driver_id"
    t.index ["location_id"], name: "index_users_on_location_id"
    t.unique_constraint ["discord_id"]
  end

  add_foreign_key "channels", "servers"
  add_foreign_key "emojis", "servers"
  add_foreign_key "events", "channels"
  add_foreign_key "events", "locations"
  add_foreign_key "users", "locations"
  add_foreign_key "users", "users", column: "driver_id"
end
