require 'sinatra/base'
#require 'sinatra/reloader'
require 'active_record'
require 'yaml'
require 'bcrypt'
require './monacoinrpc.rb'

class MonaOption < Sinatra::Base
	
	config = YAML.load_file "config.yml"
	@@wallet = MonacoinRPC.new "http://#{config["user"]}:#{config["password"]}@#{config["host"]}:#{config["port"]}"

	configure do
		Sinatra::Application.reset!
		use Rack::Reloader
		set :site_name, config["site_name"]
	end

	use ActiveRecord::ConnectionAdapters::ConnectionManagement

	ActiveRecord::Base.establish_connection(
		adapter: "sqlite3",
		database: "data/database.db"
	)

	class User < ActiveRecord::Base; end

	get '/' do
		@title = "#{config["site_name"]}へようこそ"
		
		erb :index
	end
	
	get '/register' do
		@title = "ユーザー登録"
		erb :register
	end
	
	post '/register' do
		# ハッシュ値生成(SHA256)
		salt = BCrypt::Engine.generate_salt
		hashed_password = BCrypt::Engine.hash_secret params[:password], salt
		
		User.create name: params[:name], password: hashed_password, password_salt: salt
		
		redirect '/'
	end
	
	get '/user/*' do |name|
		@user = User.find_by name: name
		halt '正しいユーザー名を指定してください'
		
		@title = name
		erb :user
	end
	
end