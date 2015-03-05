# see: https://gist.github.com/ctalkington/4448153

root = "#{Dir.getwd}"

bind "unix://#{root}/tmp/puma/socket"
pidfile "#{root}/tmp/puma/pid"
state_path "#{root}/tmp/puma/state"
rackup "#{root}/config.ru"

threads 4, 8

activate_control_app
