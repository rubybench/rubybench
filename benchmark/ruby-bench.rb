#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

class RubyBench

  class Benchmarks
    RACTOR_ONLY_PREFIX = 'ractor/'

    attr_reader :regular, :ractor_compatible, :ractor_only

    def self.parse_benchmark_file(file_path)
      new(file_path).parse
    end

    def initialize(file_path)
      @file_path = file_path
    end

    def parse
      @benchmarks_yml = YAML.load_file(@file_path)
      @ractor_compatible = @benchmarks_yml.select { |_, info| info['ractor'] == true }.keys
      @ractor_only = @benchmarks_yml.keys.map { |key| key.start_with?(RACTOR_ONLY_PREFIX) ? key.gsub(RACTOR_ONLY_PREFIX, '') : nil }.compact
      @regular = @benchmarks_yml.keys.reject { |key| key.start_with?(RACTOR_ONLY_PREFIX) }

      # Check for naming conflicts between ractor-compatible and ractor-only benchmarks
      conflicts = @ractor_compatible & @ractor_only
      if conflicts.any?
        puts "NOTE: Found benchmarks with same name in both regular and ractor-only: #{conflicts.join(', ')}"
        puts "      These will be saved with 'ractor_only_' prefix for ractor-only versions."
      end

      self
    end
  end

  rubies_path = File.expand_path('../results/rubies.yml', __dir__)
  unless File.exist?(rubies_path)
    abort "ERROR: rubies.yml not found at #{rubies_path}. Please setup using bin/prepare-results.rb"
  end
  RUBIES = YAML.load_file(rubies_path)
  RACTOR_ITERATION_PATTERN = /^\s*(\d+)\s+#\d+:\s*(\d+)ms/
  RSS_PATTERN = /^RSS:\s*([\d.]+)MiB/

  def initialize
    @started_containers = []
  end

  def run_benchmark(benchmark)
    results_file = "results/ruby-bench/#{benchmark}.yml"
    rss_file = "results/ruby-bench-rss/#{benchmark}.yml"
    run_benchmark_generic(benchmark, results_file, rss_file: rss_file, is_ractor: false)
  end

  def shutdown
    @started_containers.each do |container|
      system('docker', 'rm', '-f', container, exception: true)
    end
  end

  def run_ractor_benchmark(benchmark, ractor_only: false)
    safe_name = benchmark.gsub('/', '_')
    prefix = ractor_only  ? "ractor_only_" : ""
    category = ractor_only ? 'ractor-only' : 'ractor'
    results_file = "results/ruby-bench-ractor/#{prefix}#{safe_name}.yml"
    rss_file = "results/ruby-bench-ractor-rss/#{prefix}#{safe_name}.yml"

    run_benchmark_generic(benchmark, results_file,
      rss_file: rss_file,
      is_ractor: true,
      category: category,
      label: "ractor:#{benchmark}",
      no_pinning: true
    )
  end

  private

  def run_benchmark_generic(benchmark, results_file, rss_file: nil, is_ractor: false, category: nil, label: nil, no_pinning: false)
    if File.exist?(results_file)
      results = YAML.load_file(results_file)
    else
      results = {}
    end

    rss_results = {}
    if rss_file && File.exist?(rss_file)
      rss_results = YAML.load_file(rss_file)
    end

    target_dates = RUBIES.reject { |_, sha| sha.nil? }.keys.sort.reverse
    target_date = target_dates.find do |date|
      !results.key?(date)
    end
    if target_date.nil?
      message = "Every Ruby version is already benchmarked"
      message += " for #{label}" if label
      puts message
      return
    end
    prefix = label ? "#{label} " : ""
    puts "#{prefix}target_date: #{target_date}"

    container = setup_container(target_date, benchmark: benchmark)
    result = is_ractor ? {} : []
    rss_result = []
    timeout = 10 * 60

    [nil, '--yjit', '--zjit'].each do |opts|
      env = "env BUNDLE_JOBS=8"
      category_arg = category ? "--category #{category}" : ""
      pinning_arg = no_pinning ? "--no-pinning" : ""
      cmd = [
        'docker', 'exec', container, 'bash', '-c',
        "cd /rubybench/benchmark/ruby-bench && #{env} timeout --signal=KILL #{timeout} ./run_benchmarks.rb #{benchmark} #{category_arg} #{pinning_arg} -e 'ruby #{opts}'",
      ]
      out = IO.popen(cmd, &:read)
      puts out

      if is_ractor
        config_name = opts.nil? ? 'baseline' : opts.delete_prefix('--')
        if $?.success?
          result[config_name] = parse_ractor_output(out, benchmark)
          rss_result << parse_rss(out)
        else
          result[config_name] = nil
          rss_result << nil
        end
      else
        if $?.success?
          if line = find_benchmark_line(out, benchmark)
            result << Float(line.split(/\s+/)[1])
            rss_result << parse_rss(out)
          else
            puts "benchmark output for #{benchmark} not found"
            rss_result << nil
          end
        else
          result << nil
          rss_result << nil
        end
      end
    end
    results[target_date] = result

    FileUtils.mkdir_p(File.dirname(results_file))
    File.open(results_file, "w") do |io|
      results.sort_by(&:first).each do |date, values|
        io.puts "#{date}: #{values.to_json}"
      end
    end

    if rss_file
      rss_results[target_date] = rss_result
      FileUtils.mkdir_p(File.dirname(rss_file))
      File.open(rss_file, "w") do |io|
        rss_results.sort_by(&:first).each do |date, values|
          io.puts "#{date}: #{values.to_json}"
        end
      end
    end

    system('docker', 'exec', container, 'git', 'config', '--global', '--add', 'safe.directory', '*', exception: true)
    system('docker', 'exec', container, 'git', '-C', '/rubybench/benchmark/ruby-bench', 'clean', '-dfx', exception: true)
  end

  def find_benchmark_line(output, benchmark)
    search_pattern = benchmark.include?('/') ? benchmark.split('/').last : benchmark
    output.lines.reverse.find { |line| line.start_with?(search_pattern) }
  end

  def parse_rss(output)
    match = output.match(RSS_PATTERN)
    match ? Float(match[1]) : nil
  end

  def parse_ractor_output(output, benchmark)
    grouped = {}

    iteration_lines = output.lines.select { |line| line.match(RACTOR_ITERATION_PATTERN) }
    return nil if iteration_lines.empty?

    iteration_lines.each do |line|
      if match = line.match(RACTOR_ITERATION_PATTERN)
        ractor_count = match[1]
        time_ms = match[2].to_f

        grouped[ractor_count] ||= []
        grouped[ractor_count] << time_ms
      end
    end

    return nil if grouped.empty?
    grouped
  end

  def setup_container(target_date, benchmark:)
    container = "rubybench-#{target_date}"

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

ruby_bench = RubyBench.new
at_exit { ruby_bench.shutdown }

if ARGV.empty?
  benchmarks = RubyBench::Benchmarks.parse_benchmark_file('benchmark/ruby-bench/benchmarks.yml')

  benchmarks.regular.each do |benchmark|
    ruby_bench.run_benchmark(benchmark)
  end

  benchmarks.ractor_compatible.each do |benchmark|
    ruby_bench.run_ractor_benchmark(benchmark)
  end

  benchmarks.ractor_only.each do |benchmark|
    ruby_bench.run_ractor_benchmark(benchmark, ractor_only: true)
  end
else
  benchmarks = ARGV
  benchmarks.each do |benchmark|
    ruby_bench.run_benchmark(benchmark)
  end
end
