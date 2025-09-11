#!/usr/bin/env ruby
require 'yaml'

# 20250709 was the first version where ZJIT started working on yjit-bench.
# 20250708 is included to show that 20250709 was the first working version.
MIN_DATE = 20250708

def to_date(time)
  time.year * 10000 + time.month * 100 + time.day
end

target_dates = []
time = Time.now.utc
while (date = to_date(time)) >= MIN_DATE
  target_dates << date
  time -= 24 * 60 * 60
end

# Find target_date from target_dates that is on Docker Hub but not in rubies.yml
rubies = YAML.load_file('rubies.yml')
target_dates.select! do |date|
  next if rubies.key?(date)
  cmd = ['docker', 'pull', "ghcr.io/ruby/ruby:master-#{date}"]
  puts "+ #{cmd.join(' ')}"
  system(*cmd)
end
if target_dates.empty?
  puts "Every Ruby version already exists in rubies.yml"
  return
end

target_dates.each do |target_date|
  # Convert target_date to ruby_revision
  cmd = ['docker', 'run', '--rm', "ghcr.io/ruby/ruby:master-#{target_date}", 'ruby', '-e', 'print RUBY_REVISION']
  puts "+ #{cmd.join(' ')}"
  ruby_revision = IO.popen(cmd, &:read)
  unless $?.success?
    puts "Failed to run `#{cmd.join(' ')}`: #{ruby_revision}"
    next
  end

  # Make sure `master-#{ruby_revision}` tag also works
  cmd = ['docker', 'run', '--rm', "ghcr.io/ruby/ruby:master-#{ruby_revision}", 'ruby', '-e', 'print RUBY_REVISION']
  puts "+ #{cmd.join(' ')}"
  other_revision = IO.popen(cmd, &:read)
  unless $?.success?
    puts "Failed to run `#{cmd.join(' ')}`: #{ruby_revision}"
    next
  end
  if ruby_revision != other_revision
    puts "RUBY_REVISION mismatch on master-#{ruby_revision}: #{ruby_revision} != #{other_revision}"
    next
  end
  rubies[target_date] = ruby_revision
end

# Update rubies.yml
File.write('rubies.yml', YAML.dump(rubies.sort_by(&:first).to_h))
