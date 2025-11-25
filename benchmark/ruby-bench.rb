#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'

class RubyBench
  rubies_path = File.expand_path('../results/rubies.yml', __dir__)
  unless File.exist?(rubies_path)
    abort "ERROR: rubies.yml not found at #{rubies_path}. Please setup using bin/prepare-results.rb"
  end
  RUBIES = YAML.load_file(rubies_path)
  RACTOR_ITERATION_PATTERN = /^\s*(\d+)\s+#\d+:\s*(\d+)ms/
  attr_reader :ractor_compatible, :ractor_only

  def initialize
    @started_containers = []
    load_benchmark_metadata
  end

  def run_benchmark(benchmark)
    results_file = "results/ruby-bench/#{benchmark}.yml"
    run_benchmark_generic(benchmark, results_file, is_ractor: false)
  end

  def shutdown
    @started_containers.each do |container|
      system('docker', 'rm', '-f', container, exception: true)
    end
  end

  def run_ractor_benchmark(benchmark)
    safe_name = benchmark.gsub('/', '_')
    prefix = @ractor_only.include?(benchmark) ? "ractor_only_" : ""
    results_file = "results/ruby-bench-ractor/#{prefix}#{safe_name}.yml"
    category = @ractor_only.include?(benchmark) ? 'ractor-only' : 'ractor'

    run_benchmark_generic(benchmark, results_file,
      is_ractor: true,
      category: category,
      label: "ractor:#{benchmark}",
      no_pinning: true
    )
  end

  private

  def run_benchmark_generic(benchmark, results_file, is_ractor: false, category: nil, label: nil, no_pinning: false)
    if File.exist?(results_file)
      results = YAML.load_file(results_file)
    else
      results = {}
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
        else
          result[config_name] = nil
        end
      else
        if $?.success?
          if line = find_benchmark_line(out, benchmark)
            result << Float(line.split(/\s+/)[1])
          else
            puts "benchmark output for #{benchmark} not found"
          end
        else
          result << nil
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

    system('docker', 'exec', container, 'git', 'config', '--global', '--add', 'safe.directory', '*', exception: true)
    system('docker', 'exec', container, 'git', '-C', '/rubybench/benchmark/ruby-bench', 'clean', '-dfx', exception: true)
  end

  def load_benchmark_metadata
    @benchmarks_yml = YAML.load_file('benchmark/ruby-bench/benchmarks.yml')
    @ractor_compatible = @benchmarks_yml.select { |_, info| info['ractor'] == true }.keys
    @ractor_only = Dir.glob('benchmark/ruby-bench/benchmarks-ractor/**/benchmark.rb').map do |path|
      File.basename(File.dirname(path))
    end

    # Check for naming conflicts between ractor-compatible and ractor-only benchmarks
    conflicts = @ractor_compatible & @ractor_only
    if conflicts.any?
      puts "NOTE: Found benchmarks with same name in both regular and ractor-only: #{conflicts.join(', ')}"
      puts "      These will be saved with 'ractor_only_' prefix for ractor-only versions."
    end
  end

  def find_benchmark_line(output, benchmark)
    search_pattern = benchmark.include?('/') ? benchmark.split('/').last : benchmark
    output.lines.reverse.find { |line| line.start_with?(search_pattern) }
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
  benchmarks = YAML.load_file('benchmark/ruby-bench/benchmarks.yml').keys
  benchmarks.each do |benchmark|
    ruby_bench.run_benchmark(benchmark)
  end

  if ruby_bench.ractor_compatible.any?
    ruby_bench.ractor_compatible.each do |benchmark|
      ruby_bench.run_ractor_benchmark(benchmark)
    end
  end

  if ruby_bench.ractor_only.any?
    ruby_bench.ractor_only.each do |benchmark|
      ruby_bench.run_ractor_benchmark(benchmark)
    end
  end
else
  benchmarks = ARGV
  benchmarks.each do |benchmark|
    ruby_bench.run_benchmark(benchmark)
  end
end
