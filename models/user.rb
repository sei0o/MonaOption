require 'active_record'

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
	
	def wallet confirmations = 6
		# 現在ログイン中のユーザーのwallet残額
		@@wallet.getbalance @@config["address_prefix"] + self.id.to_s, confirmations
	end
end