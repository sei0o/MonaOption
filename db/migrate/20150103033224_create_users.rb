class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.string :name, null: false, unique: true
      t.string :password, null:false
      t.string :password_salt, null:false
      t.string :payout_address
      t.string :wallet_address, null:false, unique: true
      t.timestamps null: true
    end
  end
end
