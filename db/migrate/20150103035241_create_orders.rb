class CreateOrders < ActiveRecord::Migration
  def change
    create_table :orders do |t|
      t.string :direction, null: false
      t.integer :time, null: false
      t.integer :user_id, null: false
      t.integer :market_id, null: false
      t.decimal :amount, null: false, precision: 8, scale: 8
    end
  end
end
