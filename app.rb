#      __  ___                  ____        __  _
#     /  |/  /___  ____  ____ _/ __ \____  / /_(_)___  ____
#    / /|_/ / __ \/ __ \/ __ `/ / / / __ \/ __/ / __ \/ __ \
#   / /  / / /_/ / / / / /_/ / /_/ / /_/ / /_/ / /_/ / / / /
#  /_/  /_/\____/_/ /_/\__,_/\____/ .___/\__/_/\____/_/ /_/
#                                /_/
#
# Wow, This code seems spaghetti

require 'sinatra/base'
require 'sinatra/flash'
require 'sinatra/reloader'
require 'net/http'
require 'uri'
require 'unirest'
require 'active_record'
require 'yaml'
require 'bcrypt'
require 'json'
require 'mysql2'
require './monacoinrpc.rb'
require './models/user.rb'
require './models/order.rb'
require './autojudge.rb'

class MonaOption < Sinatra::Base

	config = YAML.load_file "config.yml"
	@@config = config
	@@wallet = MonacoinRPC.new "http://#{config["user"]}:#{config["password"]}@#{config["host"]}:#{config["port"]}"
	db_config = YAML.load_file "database.yml"
	markets_config = YAML.load_file "markets.yml"

	markets = []
	markets_config.each do |pair, param|
		from, to = pair.split "_"
		markets << {from: from, to: to, id: param["id"], payout: param["payout"]}
	end

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

		def market_of pair_or_param
			market = pair_or_param.split "_"

			if market.size == 1 # param指定の場合
				market[0]
			else
				case market
				when ["usd", "jpy"] then 1
				end
			end
		end

		def save_config
			File.open "config.yml", "w" do |file|
				YAML.dump config, file
			end
		end

		def next_judge
			Time.at @@config["last_judge"] + @@config["judge_interval"]
		end

		def last_judge
			Time.at @@config["last_judge"]
		end

		def next_deadline
			# deadlineは次のjudgeの何秒前にbetを締切るか
			Time.at next_judge.to_i - @@config["deadline"]
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
		amount = params[:amount].to_f

		if amount > login_user.wallet # payout額が多すぎる
			flash[:warning] = "出金額が多すぎます"
			redirect '/wallet/payout'
		end
		if amount <= 0
			flash[:warning] = "出金額が0以下です。"
			redirect '/wallet/payout'
		end

		unless login_user.payout_address
			flash[:warning] = "出金先アドレスが設定されていません。<a href='/settings'>設定する</a>"
			redirect '/wallet/payout'
		end

		# 支払い
		pp amount
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
		@markets = markets
		#markets_config.each do |pair, param|
		#	from, to = pair.split "_"
		#	@markets << {from: from, to: to, param: param}
		#end

		@title = "取引"
		erb :trade
	end

	post '/order' do
		content_type :json
		unless login?
			return { error: "ログインしてください" }.to_json
		end

		if params[:amount].to_f > login_user.wallet
			return { error: "残高不足です" }.to_json
		end
		if params[:amount].to_f == 0
			return { error: "0Monaかけてサーバーの資源を無駄にしないでください" }.to_json
		end
		if params[:amount].to_f < 0
			return { error: "金額をマイナスにしても、Monaはもらえません。Monaが欲しいならAskMonaやFaucetへ。" }.to_json
		end
		# deadlineを超えてる
		if params[:time].to_i > next_deadline.to_i
			return { error: "締め切りを超えています" }.to_json
		end

		puts "hoge " + params[:direction].to_s
		order = Order.create(direction: params[:direction],
												 amount: params[:amount].to_f,
												 user_id: login_user.id,
												 market_id: params[:market_id].to_i,
												 time: params[:time].to_i)

		{
			success: "取引成功"
		}.to_json
	end

	get '/api/wallet' do
		content_type :json

		unless login?
			return { error: "ログインしていません" }.to_json
		end

		data = {
			amount: login_user.wallet
		}

		data.to_json
	end

	get '/api/exchange/old/*' do |pair|
		content_type :json

		param = market_of pair

		res = Unirest.get "http://bn-options.com/fjaxs/getDealFront/a:#{param}"
		rates = res.body["tick"] # レート取り出し

		# 現在からlast_judgeの分だけ(無駄なデータを省くと同時にグラフのy軸調整のため)
		elapsed_from_last_judge = Time.new.to_i - last_judge.to_i
		rates = rates[-elapsed_from_last_judge..-1] # -interval~-1の要素

		rates.to_json
	end

	get '/api/exchange/*' do |pair|
		content_type :json

		param_rate = market_of pair

		res = Unirest.get "http://bn-options.com/fjaxs/getRateFront/a:#{param_rate}"
		rates = res.body["rate"]

		data = {
			time: rates[-1][0],
			rate: rates[-1][1]
		}

		data.to_json
	end

	get '/api/next_judge' do
		content_type :json

		{
			next: next_judge.to_i # epochで渡す
		}.to_json
	end

	get '/api/last_judge' do
		content_type :json

		{
			last: last_judge.to_i
		}.to_json
	end

	get '/api/next_deadline' do
		content_type :json

		{
			next: next_deadline.to_i
		}.to_json
	end

	post '/api/reload_config' do
		puts "reloaded / #{next_judge.to_i} / #{last_judge.to_i}"
		config = YAML.load_file "config.yml"
		@@config = config
		puts "reloaded2 / #{next_judge.to_i} / #{last_judge.to_i}"
	end

	get '/api/orders/*' do |pair|
		content_type :json

		market = market_of pair

		{
			# see: http://stackoverflow.com/questions/15427936/how-to-convert-activerecord-results-into-a-array-of-hashes
			orders: Order.where(market_id: market).map(&:serializable_hash)
		}.to_json
	end

end
