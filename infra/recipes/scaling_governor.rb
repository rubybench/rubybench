package 'cpufrequtils'

file '/etc/default/cpufrequtils' do
  content 'GOVERNOR="performance"'
end

remote_file '/etc/cron.d/disable-turbo'
