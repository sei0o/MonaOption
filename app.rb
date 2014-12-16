require 'sinatra/base'
require 'sinatra/flash'
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
		register Sinatra::Flash
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
	
	helpers do
		def login?
			!!session[:user_id]
		end
		
		def login_user
			login? ? User.find(session[:user_id])
			       : nil
		end
	end

	get '/' do
		@title = "#{config["site_name"]}へようこそ"
		
		erb :index
	end
	
	get '/register' do
		if login?
			flash[:notice] = "すでにログインしています"
			redirect '/'
		end
		
		@title = "ユーザー登録"
		erb :register
	end
	
	post '/register' do
		redirect '/logout' if login?
		
		# ハッシュ値生成
		salt = BCrypt::Engine.generate_salt
		hashed_password = BCrypt::Engine.hash_secret params[:password], salt
		
		if User.create name: params[:name], password: hashed_password, password_salt: salt
			flash[:success] = "登録に成功しました"
		end
		
		redirect '/'
	end
	
	get '/login' do
		if login?
			flash[:notice] = "すでにログインしています"
			redirect '/'
		end
		
		@title = "ログイン"
		erb :login
	end
	
	post '/login' do
		user = User.auth params[:name], params[:password]
		if user
			session[:user_id] = user.id
			redirect "/user/#{user.name}"
		else
			flash[:warning] = "ユーザー名またはパスワードが正しくありません"
			redirect '/login'
		end
	end
	
	get '/logout' do
		unless login?
			flash[:notice] = "ログインしていません"
			redirect '/'
		end
		
		session[:user_id] = nil
		
		flash[:notice] = "ログアウトしました"
		redirect '/'
	end
	
	get '/user/*' do |name|
		@user = User.find_by name: name
		unless @user
			flash[:warning] = "ユーザー名が正しくありません"
			redirect '/'
		end
		
		@title = name
		erb :user
	end
	
end