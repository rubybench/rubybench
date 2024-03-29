%w[
  eregon
].each do |u|
  user u do
    gid 27 # sudo
    shell '/bin/bash'
  end

  directory "/home/#{u}" do
    mode  '755'
    owner u
  end

  directory "/home/#{u}/.ssh" do
    mode  '700'
    owner u
  end

  remote_file "/home/#{u}/.ssh/authorized_keys" do
    mode  '600'
    owner u
  end
end

