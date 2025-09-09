#!/usr/bin/env ruby
require 'yaml'

def to_date(time)
  time.year * 10000 + time.month * 100 + time.day
end

# 20250717 was the first version where ZJIT started working on yjit-bench.
# target_dates and rubies.yml have every date that is >= 20250717.
target_dates = []
time = Time.now.utc
while (date = to_date(time)) >= 20250717
  target_dates << date
  time -= 24 * 60 * 60
end

# Find target_date from target_dates that is on Docker Hub but not in rubies.yml
rubies = YAML.load_file('rubies.yml')
target_date = target_dates.find do |date|
  next if rubies.key?(date)
  cmd = ['docker', 'pull', "ghcr.io/ruby/ruby:master-#{date}"]
  puts "+ #{cmd.join(' ')}"
  system(*cmd)
end
if target_date.nil?
  puts "Every Ruby version already exists in rubies.yml"
  return
end

# Add target_date's ruby -v to rubies
output = IO.popen(['docker', 'run', '--rm', "ghcr.io/ruby/ruby:master-#{target_date}", 'ruby', '-v'], &:read)
abort "Failed to run `ruby -v`: #{output}" unless $?.success?
rubies[target_date] = output.chomp

# Update rubies.yml
File.write('rubies.yml', YAML.dump(rubies.sort_by(&:first).to_h))
