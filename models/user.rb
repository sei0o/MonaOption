require 'active_record'
require_relative '../monacoinrpc.rb'
require_relative './order.rb'


class User < ActiveRecord::Base
	@@config = YAML.load_file "config.yml"
	@@wallet = MonacoinRPC.new "http://#{@@config["user"]}:#{@@config["password"]}@#{@@config["host"]}:#{@@config["port"]}"
	
	def self.auth name, password
		user = self.find_by name: name
		
		# パスワードのハッシュ値が等しかったら
		if user && user.password == BCrypt::Engine.hash_secret(password, user.password_salt)
			user
		else nil
		end
	end
	
	def on_order
		orders = Order.where(user_id: self.id)
		return 0 unless orders
		
		unless orders.is_a? ActiveRecord::Relation
			orders.amount
		else
			orders.inject(0) do |sum, order| # order中の総額
				sum += order.amount
			end
		end
	end
	
	def wallet confirmations = 0
		# 現在ログイン中のユーザーのwallet残額
		wallet = @@wallet.getbalance @@config["address_prefix"] + self.id.to_s, confirmations
		
		wallet - self.on_order # order中の総額を引く
	end
end