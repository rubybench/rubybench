#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

class YJITBench
  RUBIES = YAML.load_file('rubies.yml')

  def initialize
    @started_containers = []
  end

  def run_benchmark(benchmark)
    # Load past benchmark results
    if File.exist?("results/ruby-bench/#{benchmark}.yml")
      results = YAML.load_file("results/ruby-bench/#{benchmark}.yml")
    else
      results = {}
    end

    # Find a Ruby that has not been benchmarked yet
    target_dates = RUBIES.keys.sort.reverse
    target_date = target_dates.find do |date|
      !results.key?(date)
    end
    if target_date.nil?
      puts "Every Ruby version is already benchmarked"
      return
    end
    puts "target_date: #{target_date}"

    # Run benchmarks for the interpreter, YJIT, and ZJIT
    container = setup_container(target_date, benchmark: benchmark)
    result = []
    timeout = 10 * 60 # 10min
    [nil, '--yjit', '--zjit'].each do |opts|
      env = "env BUNDLE_JOBS=8"
      cmd = [
        'timeout', timeout.to_s, 'docker', 'exec', container,
        'bash', '-c', "cd /rubybench/benchmark/ruby-bench && #{env} ./run_benchmarks.rb #{benchmark} -e 'ruby #{opts}'",
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

    # Update results/ruby-bench/*.yml
    FileUtils.mkdir_p('results/ruby-bench')
    File.open("results/ruby-bench/#{benchmark}.yml", "w") do |io|
      results.sort_by(&:first).each do |date, values|
        io.puts "#{date}: #{values.to_json}"
      end
    end

    # Clean up unnecessary files
    system('docker', 'exec', container, 'git', 'config', '--global', '--add', 'safe.directory', '*', exception: true)
    system('docker', 'exec', container, 'git', '-C', '/rubybench/benchmark/ruby-bench', 'clean', '-dfx', exception: true)
  end

  def shutdown
    @started_containers.each do |container|
      system('docker', 'rm', '-f', container, exception: true)
    end
  end

  private

  def setup_container(target_date, benchmark:)
    container = "rubybench-#{target_date}"

    # Start a container
    unless @started_containers.include?(container)
      system('docker', 'rm', '-f', container, exception: true, err: File::NULL)
      system(
        'docker', 'run', '-d', '--privileged', '--name', container,
        '-v', "#{Dir.pwd}:/rubybench",
        "ghcr.io/ruby/ruby:master-#{RUBIES.fetch(target_date)}",
        'bash', '-c', 'while true; do sleep 100000; done',
        exception: true,
      )
      cmd = 'apt-get update && apt install -y build-essential git libsqlite3-dev libyaml-dev nodejs pkg-config sudo xz-utils'
      system('docker', 'exec', container, 'bash', '-c', cmd, exception: true)
      @started_containers << container
    end

    container
  end
end

yjit_bench = YJITBench.new
at_exit { yjit_bench.shutdown }

if ARGV.empty?
  benchmarks = YAML.load_file('benchmark/ruby-bench/benchmarks.yml').keys
else
  benchmarks = ARGV
end
benchmarks.each do |benchmark|
  yjit_bench.run_benchmark(benchmark)
end
