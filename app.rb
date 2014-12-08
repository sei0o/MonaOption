require 'sinatra/base'
#require 'sinatra/reloader'
require 'active_record'
require 'yaml'
require './monacoinrpc.rb'

class MonaOption < Sinatra::Base
	
	config = YAML.load_file "config.yml"
	@@wallet = MonacoinRPC.new "http://#{config["user"]}:#{config["password"]}@#{config["host"]}:#{config["port"]}"

	configure do
		Sinatra::Application.reset!
		use Rack::Reloader
	end

	use ActiveRecord::ConnectionAdapters::ConnectionManagement

	ActiveRecord::Base.establish_connection(
		adapter: "sqlite3",
		database: "data/database.db"
	)

	class Pack < ActiveRecord::Base; end
	class Ticket < ActiveRecord::Base; end

	get '/' do
		@title = "#{config["site_name"]}へようこそ"
		
		@packs = Pack.all
		
		erb :index
	end
	
end