require 'active_record'

class Order < ActiveRecord::Base
	@@config = YAML.load_file "config.yml"
	@@wallet = MonacoinRPC.new "http://#{@@config["user"]}:#{@@config["password"]}@#{@@config["host"]}:#{@@config["port"]}"
end