#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

IGNORED_BENCHMARKS = [
  # Too many benchmarks to complete in 10min. This should probably live in ruby-method-benchmarks.
  'set.yml',
]

benchmark_file = ARGV.first
if benchmark_file.nil?
  abort "Usage: #{$0} BENCHMARK_FILE"
end
if IGNORED_BENCHMARKS.include?(benchmark_file)
  puts "Ignored benchmark: #{benchmark_file}"
  return
end

# Make sure the benchmark file exists
system('test', '-f', "benchmark/ruby/benchmark/#{benchmark_file}", exception: true)
benchmark = benchmark_file.split('.', 2).first

# Load past benchmark results
name_results = Hash.new { |h, k| h[k] = {} }
Dir.glob("results/ruby/#{benchmark}/**/*.yml").each do |file|
  name = file.delete_prefix("results/ruby/#{benchmark}/").delete_suffix('.yml') # name could include /
  name_results[name] = YAML.load_file(file)
end

# Find a Ruby that has not been benchmarked yet
rubies_path = File.expand_path('../results/rubies.yml', __dir__)
unless File.exist?(rubies_path)
  abort "ERROR: rubies.yml not found at #{rubies_path}. Please setup using bin/prepare-results.rb"
end
RUBIES = YAML.load_file(rubies_path)
target_dates = RUBIES.keys.sort.reverse
if name_results.empty?
  target_date = target_dates.first
else
  target_date = target_dates.find do |date|
    name_results.any? { |_, results| !results.key?(date) }
  end
end
if target_date.nil?
  puts "Every Ruby version is already benchmarked"
  return
end
puts "target_date: #{target_date}"

# Start a container
system('docker', 'rm', '-f', 'rubybench', exception: true, err: File::NULL)
system(
  'docker', 'run', '-d', '--privileged', '--name', 'rubybench',
  '-v', "#{Dir.pwd}:/rubybench",
  "ghcr.io/ruby/ruby:master-#{RUBIES.fetch(target_date)}",
  'bash', '-c', 'while true; do sleep 100000; done',
  exception: true,
)
at_exit { system('docker', 'rm', '-f', 'rubybench', exception: true) }

# Run benchmarks for VM
timeout = 10 * 60 # 10min
cmd = [
  'timeout', timeout.to_s, 'docker', 'exec', 'rubybench', 'bash', '-c',
  "cd /rubybench/benchmark/ruby/benchmark && /rubybench/benchmark/benchmark-driver/exe/benchmark-driver #{benchmark_file} --output=simple --output-humanize=false",
]
out = IO.popen(cmd, &:read)
puts out
if $?.success?
  out.each_line do |line|
    if match = line.rstrip.match(/\A(?<name>.+)\s(?<value>\d+(\.\d+)?)\z/)
      name = match[:name].rstrip
      value = Float(match[:value])
      name_results[name][target_date] = [value]
    end
  end
else
  name_results.each do |_, results|
    results[target_date] = [nil]
  end
end

# Update results/ruby/*/*.yml
name_results.each do |name, results|
  path = "results/ruby/#{benchmark}/#{name}.yml"
  FileUtils.mkdir_p(File.dirname(path)) # do this here since name could include /
  File.open(path, "w") do |io|
    results.sort_by(&:first).each do |date, values|
      io.puts "#{date}: #{values.to_json}"
    end
  end
end

# Clean up unnecessary files
[
  ['bash', '-c', 'apt-get update && apt install -y git'],
  ['git', 'config', '--global', '--add', 'safe.directory', '*'],
  ['git', '-C', '/rubybench/benchmark/ruby', 'clean', '-dfx'],
].each do |cmd|
  cmd = ['docker', 'exec', 'rubybench', *cmd]
  puts "+ #{cmd.join(' ')}"
  system(*cmd, exception: true)
end
