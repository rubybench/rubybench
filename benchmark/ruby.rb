#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

benchmark_file = ARGV.first
if benchmark_file.nil?
  abort "Usage: #{$0} BENCHMARK_FILE"
end
system('test', '-f', "benchmark/ruby/benchmark/#{benchmark_file}", exception: true)
benchmark = benchmark_file.split('.', 2).first

# Load past benchmark results
name_results = Hash.new { |h, k| h[k] = {} }
Dir.glob("results/ruby/#{benchmark}/*.yml").each do |file|
  name = File.basename(file).delete_suffix('.yml')
  name_results[name] = YAML.load_file(file)
end

# Find a Ruby that has not been benchmarked yet
target_dates = YAML.load_file('rubies.yml').keys.reverse
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

# Start a container
system('docker', 'rm', '-f', 'rubybench', exception: true, err: File::NULL)
system(
  'docker', 'run', '-d', '--privileged', '--name', 'rubybench',
  '-v', "#{Dir.pwd}/benchmark/ruby:/ruby",
  '-v', "#{Dir.pwd}/benchmark/benchmark-driver:/benchmark-driver",
  "rubylang/ruby:master-nightly-#{target_date}-focal",
  'bash', '-c', 'while true; do sleep 100000; done',
  exception: true,
)
at_exit { system('docker', 'rm', '-f', 'rubybench', exception: true) }

# Run benchmarks for VM
timeout = 10 * 60 # 10min
cmd = [
  'timeout', timeout.to_s, 'docker', 'exec', 'rubybench', 'bash', '-c',
  "cd /ruby/benchmark && /benchmark-driver/exe/benchmark-driver #{benchmark_file} --output=simple --output-humanize=false",
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
FileUtils.mkdir_p("results/ruby/#{benchmark}")
name_results.each do |name, results|
  File.open("results/ruby/#{benchmark}/#{name}.yml", "w") do |io|
    results.sort_by(&:first).each do |date, values|
      io.puts "#{date}: #{values.to_json}"
    end
  end
end
