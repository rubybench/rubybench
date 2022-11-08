package 'docker.io'

execute 'usermod -aG docker k0kubun' do
  not_if 'groups k0kubun | grep docker -w'
end
