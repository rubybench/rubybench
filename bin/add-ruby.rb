#!/usr/bin/env ruby
require 'yaml'

def to_date(time)
  time.year * 10000 + time.month * 100 + time.day
end

# 20230307 was the first version that added RJIT.
# So target_dates and rubies.yml have every date that is >= 20220923.
target_dates = []
time = Time.now.getlocal("+09:00") # workaround until ruby-docker-images fixes it
while (date = to_date(time)) >= 20230307
  target_dates << date
  time -= 24 * 60 * 60
end

# Find target_date from target_dates that is on Docker Hub but not in rubies.yml
rubies = YAML.load_file('rubies.yml')
target_date = target_dates.find do |date|
  !rubies.key?(date) && system('docker', 'pull', "rubylang/ruby:master-nightly-#{date}-focal")
end
if target_date.nil?
  puts "Every Ruby version already exists in rubies.yml"
  return
end

# Add target_date's ruby -v to rubies
output = IO.popen(['docker', 'run', '--rm', "rubylang/ruby:master-nightly-#{target_date}-focal", 'ruby', '-v'], &:read)
abort "Failed to run `ruby -v`: #{output}" unless $?.success?
rubies[target_date] = output.chomp

# Update rubies.yml
File.write('rubies.yml', YAML.dump(rubies.sort_by(&:first).to_h))
