#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'
require_relative '../lib/yjit_stats_processor'
require_relative '../lib/exit_report_formatter'

class YJITBench
  rubies_path = File.expand_path('../results/rubies.yml', __dir__)
  unless File.exist?(rubies_path)
    abort "ERROR: rubies.yml not found at #{rubies_path}. Please setup using bin/prepare-results.rb"
  end
  RUBIES = YAML.load_file(rubies_path)
  RACTOR_ITERATION_PATTERN = /^\s*(\d+)\s+#\d+:\s*(\d+)ms/
  attr_reader :ractor_compatible, :ractor_only

  def initialize(collect_stats: false)
    @started_containers = []
    @collect_stats = collect_stats
    load_benchmark_metadata
    puts "YJIT stats collection: #{@collect_stats ? 'enabled' : 'disabled'}" if @collect_stats
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
      label: "ractor:#{benchmark}"
    )
  end

  private

  def run_benchmark_generic(benchmark, results_file, is_ractor: false, category: nil, label: nil)
    if File.exist?(results_file)
      results = YAML.load_file(results_file)
    else
      results = {}
    end

    target_dates = RUBIES.keys.sort.reverse
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

    # Collect YJIT stats if enabled
    yjit_stats = nil
    zjit_stats = nil

    [nil, '--yjit', '--zjit'].each do |opts|
      env = "env BUNDLE_JOBS=8"
      category_arg = category ? "--category #{category}" : ""
      cmd = [
        'docker', 'exec', container, 'bash', '-c',
        "cd /rubybench/benchmark/ruby-bench && #{env} timeout --signal=KILL #{timeout} ./run_benchmarks.rb #{benchmark} #{category_arg} -e 'ruby #{opts}'",
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

          # Collect YJIT stats after successful benchmark run
          if @collect_stats && opts == '--yjit' && !is_ractor
            puts "Collecting YJIT stats for #{benchmark}..."
            yjit_stats = collect_jit_stats(container, 'yjit')
          elsif @collect_stats && opts == '--zjit' && !is_ractor
            puts "Collecting ZJIT stats for #{benchmark}..."
            zjit_stats = collect_jit_stats(container, 'zjit')
          end
        else
          result << nil
        end
      end
    end
    results[target_date] = result

    # Process and store YJIT stats if collected
    if @collect_stats && !is_ractor
      process_and_store_stats(benchmark, target_date, yjit_stats, zjit_stats)
    end

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

  def collect_jit_stats(container, jit_type)
    # Run the stats collection script inside the container
    cmd = [
      'docker', 'exec', container, 'ruby',
      "/rubybench/benchmark/collect_yjit_stats.rb"
    ]

    stats_json = IO.popen(cmd, &:read)

    if $?.success?
      begin
        stats = JSON.parse(stats_json)
        return stats unless stats['error']
        puts "Stats collection error: #{stats['error']}"
      rescue JSON::ParserError => e
        puts "Failed to parse stats JSON: #{e.message}"
      end
    else
      puts "Stats collection failed for #{jit_type}"
    end

    nil
  end

  def process_and_store_stats(benchmark, date, yjit_stats, zjit_stats)
    ruby_sha = RUBIES[date]

    # Process YJIT stats
    if yjit_stats
      processed_stats = YJITStatsProcessor.process_stats(yjit_stats)
      if processed_stats
        # Save essential stats to YAML
        save_essential_stats(benchmark, date, processed_stats, 'yjit')

        # Generate and save exit report
        full_stats = YJITStatsProcessor.extract_full_stats_for_report(yjit_stats)
        save_exit_report(benchmark, date, ruby_sha, full_stats, 'yjit')
      end
    end

    # Process ZJIT stats if available (future-proofing)
    if zjit_stats
      processed_stats = YJITStatsProcessor.process_stats(zjit_stats)
      if processed_stats
        save_essential_stats(benchmark, date, processed_stats, 'zjit')

        full_stats = YJITStatsProcessor.extract_full_stats_for_report(zjit_stats)
        save_exit_report(benchmark, date, ruby_sha, full_stats, 'zjit')
      end
    end
  end

  def save_essential_stats(benchmark, date, stats, jit_type)
    stats_file = "results/#{jit_type}-stats/#{benchmark}.yml"

    # Load existing stats or create new
    if File.exist?(stats_file)
      all_stats = YAML.load_file(stats_file)
    else
      all_stats = {}
    end

    # Add new stats for this date
    all_stats[date] = stats

    # Write back to file
    FileUtils.mkdir_p(File.dirname(stats_file))
    File.open(stats_file, 'w') do |f|
      all_stats.sort_by(&:first).each do |d, s|
        f.puts "#{d}: #{s.to_json}"
      end
    end

    puts "Saved #{jit_type} stats for #{benchmark} (#{date})"
  end

  def save_exit_report(benchmark, date, ruby_sha, stats, jit_type)
    report_dir = "results/exit-reports/#{date}"
    report_file = "#{report_dir}/#{benchmark}_#{jit_type}.txt"

    # Generate the report
    report = ExitReportFormatter.generate_report(benchmark, date, ruby_sha, stats)

    # Write to file
    FileUtils.mkdir_p(report_dir)
    File.write(report_file, report)

    puts "Generated exit report: #{report_file}"
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

# Parse command-line options
collect_stats = false
benchmarks_to_run = []

ARGV.each do |arg|
  if arg == '--collect-stats'
    collect_stats = true
  else
    benchmarks_to_run << arg
  end
end

yjit_bench = YJITBench.new(collect_stats: collect_stats)
at_exit { yjit_bench.shutdown }

if benchmarks_to_run.empty?
  benchmarks = YAML.load_file('benchmark/ruby-bench/benchmarks.yml').keys
  benchmarks.each do |benchmark|
    yjit_bench.run_benchmark(benchmark)
  end

  if yjit_bench.ractor_compatible.any?
    yjit_bench.ractor_compatible.each do |benchmark|
      yjit_bench.run_ractor_benchmark(benchmark)
    end
  end

  if yjit_bench.ractor_only.any?
    yjit_bench.ractor_only.each do |benchmark|
      yjit_bench.run_ractor_benchmark(benchmark)
    end
  end
else
  benchmarks_to_run.each do |benchmark|
    yjit_bench.run_benchmark(benchmark)
  end
end
