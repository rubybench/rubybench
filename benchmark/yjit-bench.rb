#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

class YJITBench
  def initialize
    @started_containers = []
    @updated_containers = []
  end

  def run_benchmark(benchmark)
    # Load past benchmark results
    if File.exist?("results/yjit-bench/#{benchmark}.yml")
      results = YAML.load_file("results/yjit-bench/#{benchmark}.yml")
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

    # Run benchmarks for the interpreter, YJIT, and RJIT
    container = setup_container(target_date, benchmark: benchmark)
    result = []
    timeout = 10 * 60 # 10min
    [nil, '--yjit', '--rjit'].each do |opts|
      env = "env BUNDLE_JOBS=8"
      cmd = [
        'timeout', timeout.to_s, 'docker', 'exec', container,
        'bash', '-c', "cd /rubybench/benchmark/yjit-bench && #{env} ./run_benchmarks.rb #{benchmark} -e 'ruby #{opts}'",
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

    # Update results/yjit-bench/*.yml
    FileUtils.mkdir_p('results/yjit-bench')
    File.open("results/yjit-bench/#{benchmark}.yml", "w") do |io|
      results.sort_by(&:first).each do |date, values|
        io.puts "#{date}: #{values.to_json}"
      end
    end

    # Clean up unnecessary files
    system('docker', 'exec', container, 'git', 'config', '--global', '--add', 'safe.directory', '*', exception: true)
    system('docker', 'exec', container, 'git', '-C', '/rubybench/benchmark/yjit-bench', 'clean', '-dfx', exception: true)
  end

  def shutdown
    #@started_containers.each do |container|
    #  system('docker', 'rm', '-f', container, exception: true)
    #end
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
        "rubylang/ruby:master-nightly-#{target_date}-focal",
        'bash', '-c', 'while true; do sleep 100000; done',
        exception: true,
      )
      @started_containers << container
    end

    # Prepare for running benchmarks
    if File.exist?("benchmark/yjit-bench/benchmarks/#{benchmark}/Gemfile")
      unless @updated_containers.include?(container)
        cmd = 'apt-get update && apt install -y build-essential libsqlite3-dev libyaml-dev pkg-config xz-utils'
        system('docker', 'exec', container, 'bash', '-c', cmd, exception: true)
        @updated_containers << container
      end
    end

    container
  end
end

yjit_bench = YJITBench.new
at_exit { yjit_bench.shutdown }

if ARGV.empty?
  benchmarks = YAML.load_file('benchmark/yjit-bench/benchmarks.yml').keys
else
  benchmarks = ARGV
end
benchmarks.each do |benchmark|
  yjit_bench.run_benchmark(benchmark)
end
