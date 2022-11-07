#!/usr/bin/env ruby
require 'yaml'
require 'json'

benchmark = ARGV.first
if benchmark.nil?
  abort "Usage: #{$0} BENCHMARK"
end

# Load past benchmark results
if File.exist?("results/#{benchmark}.yml")
  results = YAML.load_file("results/#{benchmark}.yml")
else
  results = {}
end

# Find a Ruby that has not been benchmarked yet
target_dates = YAML.load_file('rubies.yml').keys.reverse
target_date = target_dates.find do |date|
  !results.key?(date)
end
if target_date.nil?
  puts "Every Ruby version is already benchmarked"
  return
end

# Start a container
system(
  'docker', 'run', '-d', '--privileged', '--name', 'rubybench',
  '-v', "#{Dir.pwd}/yjit-bench:/yjit-bench",
  "rubylang/ruby:master-nightly-#{target_date}-focal",
  'bash', '-c', 'while true; do sleep 100000; done',
  exception: true,
)
at_exit { system('docker', 'rm', '-f', 'rubybench', exception: true) }

# Prepare for running benchmarks
# TODO: Install dependency for railsbench

# Run benchmarks for VM, MJIT, and YJIT
result = []
timeout = 10 * 60 # 10min
[nil, '--mjit', '--yjit'].each do |opts|
  cmd = [
    'timeout', timeout.to_s, 'docker', 'exec', 'rubybench',
    'bash', '-c', "cd /yjit-bench && ./run_benchmarks.rb #{benchmark} -e 'ruby #{opts}'",
  ]
  out = IO.popen(cmd, &:read)
  puts out
  if $?.success?
    line = out.lines.reverse.find { |line| line.start_with?(benchmark) }
    result << Float(line.split(/\s+/)[1])
  else
    result << nil
  end
end
results[target_date] = result

# Update results/*.yml
File.open("results/#{benchmark}.yml", "w") do |io|
  results.sort_by(&:first).each do |date, times|
    io.puts "#{date}: #{times.to_json}"
  end
end
