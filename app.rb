require 'sinatra/base'
require 'sinatra/flash'
require 'sinatra/reloader'
require 'net/http'
require 'uri'
require 'active_record'
require 'yaml'
require 'bcrypt'
require 'json'
require 'mysql2'
require './monacoinrpc.rb'
require './models/user.rb'

class MonaOption < Sinatra::Base
	
	config = YAML.load_file "config.yml"
	db_config = YAML.load_file "database.yml"
	markets_config = YAML.load_file "markets.yml"
	@@wallet = MonacoinRPC.new "http://#{config["user"]}:#{config["password"]}@#{config["host"]}:#{config["port"]}"

	configure do
		Sinatra::Application.reset!
		#use Rack::Reloader
		enable :sessions
		register Sinatra::Reloader
		register Sinatra::Flash
		set :site_name, config["site_name"]
	end
		
	helpers do
		def login?
			!!session[:user_id]
		end
		
		def login_user
			login? ? User.find(session[:user_id])
			       : nil
		end
		
		def user_only message = "ログインしていません"
			unless login?
				flash[:notice] = message
				redirect '/'
			end
		end
	end
		
	use ActiveRecord::ConnectionAdapters::ConnectionManagement
	ActiveRecord::Base.establish_connection(db_config["development"])

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
		redirect '/' if login?
		
		# 重複確認
		if User.exists? name: params[:name]
			flash[:warning] = "そのユーザー名はすでに存在します"
			redirect '/register'
		end
		
		# ハッシュ値生成
		salt = BCrypt::Engine.generate_salt
		hashed_password = BCrypt::Engine.hash_secret params[:password], salt
		
		user = User.create(name: params[:name],
									 password: hashed_password,
									 password_salt: salt,
									 wallet_address: @@wallet.getnewaddress) # 入出金用のアドレス
		if user
			# account設定
			@@wallet.setaccount user.wallet_address, config["address_prefix"] + user.id.to_s
			flash[:success] = "登録に成功しました。右上からログインしてください"
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
		user_only
		
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
	
	get '/settings' do
		user_only

		@title = "設定"
		erb :settings
	end

	post '/change' do
		unless @@wallet.validateaddress(params[:address])["isvalid"]
			flash[:warning] = "アドレスが正しくありません"
			redirect "/settings"
		end
		
		user = login_user
		user.payout_address = params[:address]
		user.save
		
		flash[:success] = "保存に成功しました"
		redirect "/settings"
	end
	
	get '/wallet/deposit' do
		user_only
		
		@title = "入金"
		erb :deposit
	end
	
	get '/wallet/payout' do
		user_only
		
		@title = "出金"
		erb :payout
	end
	
	post '/wallet/payout' do
		amount = params[:amount].to_i
		
		if amount > login_user.wallet # payout額が多すぎる
			flash[:warning] = "出金額が多すぎます"
			redirect '/wallet/payout'
		end
		
		unless login_user.payout_address
			flash[:warning] = "出金先アドレスが設定されていません。<a href='/settings'>設定する</a>"
			redirect '/wallet/payout'
		end
		
		# 支払い
		@@wallet.walletpassphrase config["wallet_passphrase"], 10
		@@wallet.sendtoaddress login_user.payout_address, amount
		@@wallet.walletlock
		
		# ユーザーのwalletから減らす
		# ""という名前のアカウントから支払われるのでそこに転送する
		@@wallet.move config["address_prefix"] + login_user.id.to_s, "", amount
		
		flash[:success] = "出金に成功しました"
		redirect '/'
	end
	
	get '/trade' do
		@markets = []
		markets_config.each do |pair, param|
			from, to = pair.split "_"
			@markets << {from: from, to: to, param: param}
		end
		
		@title = "取引"
		erb :trade
	end
	
	get '/api/wallet' do
		content_type :json
		
		data = {
			amount: login_user.wallet
		}
		
		data.to_json
	end
	
	get '/api/exchange/*' do |pair|
		content_type :json
		
		market = pair.split "_"
		
		param_rate =
		if market.size == 1 # param指定の場合
			market[0]
		else
			case market
			when ["usd", "jpy"] then 1
			end
		end
		
		uri = URI.parse "http://bn-options.com/fjaxs/getRateFront/a:#{param_rate}"
		req = Net::HTTP::Get.new uri.request_uri
		res = nil
		
		Net::HTTP.new(uri.host, uri.port).start do |h|
			res = h.request req
		end
		
		# レスポンスからレートだけ取り出し
		rates = JSON.parse(res.body)["rate"]
		
		data = {
			time: rates[-1][0],
			rate: rates[-1][1]
		}
		
		data.to_json
	end
	
end