require 'sinatra/base'
#require 'sinatra/reloader'
require 'active_record'
require 'yaml'
require 'bcrypt'
require 'mysql2'
require './monacoinrpc.rb'

class MonaOption < Sinatra::Base
	
	config = YAML.load_file "config.yml"
	db_config = YAML.load_file "database.yml"
	@@wallet = MonacoinRPC.new "http://#{config["user"]}:#{config["password"]}@#{config["host"]}:#{config["port"]}"

	configure do
		Sinatra::Application.reset!
		use Rack::Reloader
		enable :sessions
		set :site_name, config["site_name"]
	end

	use ActiveRecord::ConnectionAdapters::ConnectionManagement
	
	ActiveRecord::Base.establish_connection(db_config["development"])
	

	class User < ActiveRecord::Base
		def self.auth name, password
			user = self.find_by name: name
			
			# パスワードのハッシュ値が等しかったら
			if user && user.password == BCrypt::Engine.hash_secret(password, user.password_salt)
				user
			else nil
			end
		end
	end

	get '/' do
		@title = "#{config["site_name"]}へようこそ"
		
		erb :index
	end
	
	get '/register' do
		@title = "ユーザー登録"
		erb :register
	end
	
	post '/register' do
		redirect '/logout' if session[:user_id]
		
		# ハッシュ値生成
		salt = BCrypt::Engine.generate_salt
		hashed_password = BCrypt::Engine.hash_secret params[:password], salt
		
		User.create name: params[:name], password: hashed_password, password_salt: salt
		
		redirect '/'
	end
	
	get '/login' do
		redirect '/logout' if session[:user_id]
		
		@title = "ログイン"
		erb :login
	end
	
	post '/login' do
		user = User.find_by name: params[:name]
		if User.auth params[:name], params[:password]
			session[:user_id] = user.id
			redirect "/user/#{user.name}"
		else
			redirect '/login'
		end
	end
	
	get '/logout' do
		redirect '/login' unless session[:user_id]
		
		session[:user_id] = nil
		
		redirect '/'
	end
	
	get '/user/*' do |name|
		@user = User.find_by name: name
		halt '正しいユーザー名を指定してください' unless @user
		
		@title = name
		erb :user
	end
	
end