# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150103035241) do

  create_table "orders", force: :cascade do |t|
    t.string  "direction", limit: 255,                         null: false
    t.integer "time",      limit: 4,                           null: false
    t.integer "user_id",   limit: 4,                           null: false
    t.integer "market_id", limit: 4,                           null: false
    t.decimal "amount",                precision: 8, scale: 8, null: false
  end

  create_table "users", force: :cascade do |t|
    t.string   "name",           limit: 255, null: false
    t.string   "password",       limit: 255, null: false
    t.string   "password_salt",  limit: 255, null: false
    t.string   "payout_address", limit: 255
    t.string   "wallet_address", limit: 255, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
