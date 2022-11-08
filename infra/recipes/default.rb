include_recipe 'docker'
include_recipe 'rubybench'

remote_file '/lib/systemd/system/rubybench.service' do
  mode '600'
  owner 'root'
  group 'root'
end

remote_file '/lib/systemd/system/rubybench.timer' do
  mode '600'
  owner 'root'
  group 'root'
end

service 'rubybench.timer' do
  action [:start, :enable]
end
