#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

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
case benchmark
when 'activerecord', 'erubi', 'erubi_rails', 'railsbench'
  cmd = 'apt-get update && apt install -y libsqlite3-dev xz-utils'
  system('docker', 'exec', 'rubybench', 'bash', '-c', cmd, exception: true)
end

# Run benchmarks for VM, MJIT, and YJIT
result = []
timeout = 10 * 60 # 10min
[nil, '--mjit', '--yjit'].each do |opts|
  env = "env BUNDLE_JOBS=8 #{ENV['YJIT_BENCH_ENV']}"
  cmd = [
    'timeout', timeout.to_s, 'docker', 'exec', 'rubybench',
    'bash', '-c', "cd /yjit-bench && #{env} ./run_benchmarks.rb #{benchmark} -e 'ruby #{opts}'",
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
FileUtils.mkdir_p('results')
File.open("results/#{benchmark}.yml", "w") do |io|
  results.sort_by(&:first).each do |date, times|
    io.puts "#{date}: #{times.to_json}"
  end
end

# Clean up unnecessary files
system('docker', 'exec', 'rubybench', 'rm', '-rf', '/yjit-bench/data', exception: true)
