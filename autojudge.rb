require 'yaml'
require 'json'
require 'mysql2'
require 'unirest'
require 'net/http'
require 'uri'
require 'pp'
require 'active_record'
require './models/user.rb'
require './models/order.rb'
require './monacoinrpc.rb'

config = YAML.load_file "config.yml"
db_config = YAML.load_file "database.yml"
markets_config = YAML.load_file "markets.yml"

# ここが実行されるのはサーバー起動時の一回だけ
# だから、last_judgeを現在時刻に設定しておく
# そうしないと、最終判断時刻と現在時刻に間ができて、
# loop doの次のif next_judge <= Time.now.to_i
# が常に成立してしまう
# example: (ログ)
# NOW: 1419404287
# JUDGE! NOW:1419404287 / LAST:1419404121 / NEXT:1419404135
# (このときのLASTは前回サーバー起動時のものだから間が空いてしまっている)
config["last_judge"] = Time.now.to_i
File.open "config.yml", "w" do |file| 
  YAML.dump config, file
end

ActiveRecord::Base.establish_connection(db_config["development"])

wallet = MonacoinRPC.new "http://#{config["user"]}:#{config["password"]}@#{config["host"]}:#{config["port"]}"

t1 = Thread.start do
  loop do
		
		next_judge = config["last_judge"] + config["judge_interval"]
		
    # 現在時刻が次の判断すべき時刻を過ぎている
    if next_judge <= Time.now.to_i
			
      puts "JUDGE! NOW:#{Time.now.to_i} / LAST:#{config["last_judge"]} / NEXT:#{next_judge}"
			
			# ordersテーブルを元にbetを徴収
			Order.all.each do |order|
				wallet.move config["address_prefix"] + order.user_id.to_s, config["wallet_account"], order.amount
			end
			
			puts "--------MOVED--------"
			puts "wallet: #{wallet.getbalance config["wallet_account"]}"

			# /api/からレートを取得(まだlast_judgeは更新していないので、前の判断から今までのrateが返ってくる)
			rates = []
			markets_config.each do |pair, param|
				res = Unirest.get "http://#{config["server_host"]}:#{config["server_port"]}/api/exchange/old/#{param}"
				rates[param] = res.body
			end
			
			# 判断
			payouts = {} # 支払いリスト
			Order.all.each do |order|
				order_rate = 0
				rates[order.market_id].each do |rate| # 当該marketのうちから
					if rate[0] == order.time # orderされた時間と等しい時間の[time,rate]
						order_rate = rate[1]
						break
					end
				end
				# 見つからない -> 今回の期間に入らない
				next if order_rate == 0
				
				judge_rate = rates[order.market_id][-1][1] # 直近のrate
				if (order.direction == "high" && order_rate < judge_rate) || # highでjudge時のrateが上回っていたら
		  		 (order.direction == "low"  && order_rate > judge_rate)    # low で下回っていたら
		  		print "WIN: "
		  		# monaoption用のアドレスに送金
					payout_account = config["address_prefix"] + order.user_id.to_s
				  payout_address = wallet.getaddressesbyaccount(payout_account)[0]
					payouts[payout_address] = order.amount * 1.2 # とりあえずペイアウトは1.2
				else print "LOSE: " end
				puts "#{order.amount} / order: #{order_rate} / judge: #{judge_rate} / dir: #{order.direction}"
			end
			pp payouts
			
			# 一気に支払い
			wallet.walletpassphrase config["wallet_passphrase"], 3
			pp wallet.sendmany config["wallet_account"], payouts unless payouts.empty?
			wallet.walletlock
			
			# order削除 & ログ
			Order.destroy_all
			
			# 最終判断時刻を更新
    	config["last_judge"] = next_judge
			File.open "config.yml", "w" do |file|
				YAML.dump config, file
			end
			
			# app.rb側のconfigも再読み込みさせる(このやり方で良いのだろうか)
			begin
        Unirest.post "http://#{config["server_host"]}:#{config["server_port"]}/api/reload_config"
      rescue
        puts "reload失敗"
			end
    end
    
    sleep config["check_interval"]
  end
end

t1.abort_on_exception = true