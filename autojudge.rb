require 'yaml'
require 'json'
require 'uri'
require 'net/http'

config = YAML.load_file "config.yml"

# 今まで一度もhigh/lowの判断をしたことがない場合、現在時刻をlast_judgeにする
unless config["last_judge"]
  config["last_judge"] = Time.now.to_i
  File.open "config.yml", "w" do |file|
  	YAML.dump config, file
  end
end

next_judge = config["last_judge"] + config["judge_interval"]

t1 = Thread.start do
  loop do
    # 現在時刻が次の判断すべき時刻を過ぎている
    puts "NOW: #{Time.now.to_i}"
    if next_judge <= Time.now.to_i
      puts "JUDGE! NOW:#{Time.now.to_i} / LAST:#{config["last_judge"]} / NEXT:#{next_judge}"
      
      # 最終判断時刻を更新
    	config["last_judge"] = next_judge
			File.open "config.yml", "w" do |file|
				YAML.dump config, file
			end
			
			next_judge = config["last_judge"] + config["judge_interval"] # 次の判断に備えて更新
			
			# app.rb側のconfigも再読み込みさせる(このやり方で良いのだろうか)
			begin
        uri = URI.parse "http://#{config["server_host"]}:#{config["server_port"]}/api/reload_config"
        req = Net::HTTP::Post.new uri.request_uri
      
        Net::HTTP.new(uri.host, uri.port).start do |h|
        	h.request req
        end
      rescue
        puts "reload失敗"
			end
			
			# 判断
    end
    
    sleep config["check_interval"]
  end
end

t1.abort_on_exception = true