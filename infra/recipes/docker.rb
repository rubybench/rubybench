package 'docker.io'

execute 'usermod -aG docker k0kubun' do
  not_if 'groups k0kubun | grep docker -w'
end

remote_file '/etc/fstab' do
  owner 'root'
  group 'root'
  mode '644'
end

# https://www.ibm.com/docs/en/cloud-private/3.1.1?topic=pyci-specifying-default-docker-storage-directory-by-using-bind-mount
# sudo systemctl stop docker
# sudo rm -rf /var/lib/docker
# sudo mkdir /var/lib/docker
# sudo mkdir /mnt/docker
# sudo mount --rbind /mnt/docker /var/lib/docker
# sudo systemctl start docker
