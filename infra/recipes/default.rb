include_recipe 'users'
include_recipe 'docker'
include_recipe 'rubybench'
include_recipe 'scaling_governor'

execute 'systemctl daemon-reload' do
  action :nothing
end

remote_file '/lib/systemd/system/rubybench.service' do
  mode '600'
  owner 'root'
  group 'root'
  notifies :run, 'execute[systemctl daemon-reload]'
end

remote_file '/lib/systemd/system/rubybench.timer' do
  mode '600'
  owner 'root'
  group 'root'
  notifies :run, 'execute[systemctl daemon-reload]'
end

service 'rubybench.timer' do
  action [:start, :enable]
end
