package 'ruby'

execute 'git clone --recursive https://github.com/rubybench/rubybench /home/k0kubun/rubybench' do
  user 'k0kubun'
  not_if 'test -d /home/k0kubun/rubybench'
end

remote_file '/home/k0kubun/.gitconfig' do
  owner 'k0kubun'
  group 'k0kubun'
  mode '644'
end

# $ ssh-keygen
# Set it as a deploy key
