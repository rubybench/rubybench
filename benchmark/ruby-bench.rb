#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'yaml'
require 'optparse'
require 'open3'

class YJITBench
  rubies_path = File.expand_path('../results/rubies.yml', __dir__)
  unless File.exist?(rubies_path)
    abort "ERROR: rubies.yml not found at #{rubies_path}. Please setup using bin/prepare-results.rb"
  end
  RUBIES = YAML.load_file(rubies_path)
  RACTOR_ITERATION_PATTERN = /^\s*(\d+)\s+#\d+:\s*(\d+)ms/
  attr_reader :ractor_compatible, :ractor_only, :collect_yjit_stats

  def initialize(collect_yjit_stats: false)
    @started_containers = []
    @collect_yjit_stats = collect_yjit_stats
    load_benchmark_metadata

    # Only load stats processor if needed
    if @collect_yjit_stats
      require_relative '../lib/yjit_stats_processor'
    end
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

    # Pre-flight check: Verify YJIT support if stats collection is enabled
    if @collect_yjit_stats && !check_yjit_support(container)
      raise "YJIT stats collection was requested but YJIT is not available in Ruby #{target_date}"
    end
    result = is_ractor ? {} : []
    yjit_stats = nil
    timeout = 10 * 60

    [nil, '--yjit', '--zjit'].each do |opts|
      env = "env BUNDLE_JOBS=8"
      category_arg = category ? "--category #{category}" : ""

      # Determine how to run the benchmark
      if opts == '--yjit' && @collect_yjit_stats
        # Copy wrapper script to container
        copy_wrapper_to_container(container)

        # Use wrapper script for YJIT with stats collection
        cmd = [
          'docker', 'exec', container, 'bash', '-c',
          "cd /rubybench/benchmark/ruby-bench && #{env} timeout --signal=KILL #{timeout} " \
          "ruby --yjit --yjit-stats /rubybench/benchmark/yjit_stats_wrapper.rb #{benchmark} #{category_arg}",
        ]
      else
        # Normal benchmark run
        ruby_opts = opts
        cmd = [
          'docker', 'exec', container, 'bash', '-c',
          "cd /rubybench/benchmark/ruby-bench && #{env} timeout --signal=KILL #{timeout} " \
          "./run_benchmarks.rb #{benchmark} #{category_arg} -e 'ruby #{ruby_opts}'",
        ]
      end

      # Capture both stdout and stderr for stats collection
      out, err, status = Open3.capture3(*cmd)

      # Always show stdout (benchmark results)
      puts out

      # Show stderr if there are any errors/warnings (excluding our stats markers)
      if err && !err.empty?
        # Filter out our own stats markers when showing stderr
        filtered_err = err.gsub(/===YJIT_STATS_(START|END|ERROR|ERROR_END)===.*?===YJIT_STATS_(END|ERROR_END)===/m, '')
        filtered_err = filtered_err.strip

        if !filtered_err.empty? && !@collect_yjit_stats
          # Show all stderr if not collecting stats
          warn "Benchmark stderr output:"
          warn filtered_err
        elsif !filtered_err.empty? && ENV['DEBUG_YJIT_STATS']
          # In debug mode, show filtered stderr
          warn "DEBUG: Benchmark stderr (filtered):"
          warn filtered_err
        end
      end

      if is_ractor
        config_name = opts.nil? ? 'baseline' : opts.delete_prefix('--')
        if status.success?
          result[config_name] = parse_ractor_output(out, benchmark)
        else
          result[config_name] = nil
        end
      else
        if status.success?
          if line = find_benchmark_line(out, benchmark)
            result << Float(line.split(/\s+/)[1])
          else
            puts "benchmark output for #{benchmark} not found"
            result << nil
          end

          # Extract YJIT stats if this was a YJIT run with stats enabled
          if opts == '--yjit' && @collect_yjit_stats && defined?(YJITStatsProcessor)
            # Extract from stderr (wrapper output)
            extracted_stats = extract_yjit_stats_from_output(err)

            if extracted_stats.nil?
              # This is a critical failure - we expected stats but didn't get them
              warn "CRITICAL ERROR: YJIT stats collection was enabled but no stats were found"
              warn "Benchmark: #{benchmark}"
              warn "Stderr output (first 1000 chars): #{err[0..999]}"
              warn "This likely means:"
              warn "  1. The wrapper script failed to load"
              warn "  2. YJIT is not available in this Ruby build"
              warn "  3. The benchmark crashed before stats could be collected"
              raise "YJIT stats collection failed for #{benchmark} - cannot continue"
            end

            yjit_stats = YJITStatsProcessor.process_stats(extracted_stats)
            if yjit_stats.nil?
              warn "ERROR: YJIT stats were collected but failed validation"
              warn "This likely means stats are empty or corrupted"
              raise "YJIT stats validation failed for #{benchmark}"
            end
          end
        else
          result << nil
        end
      end
    end

    # Store result with optional YJIT stats
    if yjit_stats && !yjit_stats.empty?
      results[target_date] = { 'times' => result, 'yjit_stats' => yjit_stats }
    else
      results[target_date] = result
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

  def check_yjit_support(container)
    puts "Checking YJIT support in container..." if ENV['DEBUG_YJIT_STATS']

    # Check if YJIT is available and can be enabled
    check_script = <<~RUBY
      begin
        if defined?(RubyVM::YJIT)
          if RubyVM::YJIT.respond_to?(:enable)
            RubyVM::YJIT.enable
            puts "YJIT_OK"
            exit 0
          else
            puts "YJIT defined but cannot be enabled"
            exit 1
          end
        else
          puts "YJIT not defined"
          exit 1
        end
      rescue => e
        puts "Error checking YJIT: \#{e.message}"
        exit 1
      end
    RUBY

    cmd = ['docker', 'exec', container, 'ruby', '--yjit', '-e', check_script]
    output = IO.popen(cmd, err: [:child, :out], &:read)

    if $?.success? && output.include?('YJIT_OK')
      puts "YJIT support confirmed" if ENV['DEBUG_YJIT_STATS']
      true
    else
      warn "YJIT support check failed:"
      warn "Output: #{output}"
      false
    end
  end

  def copy_wrapper_to_container(container)
    # The wrapper script is already mounted via volume, no need to copy
    # Just verify it exists
    wrapper_path = '/rubybench/benchmark/yjit_stats_wrapper.rb'
    check_cmd = ['docker', 'exec', container, 'test', '-f', wrapper_path]
    system(*check_cmd, out: File::NULL, err: File::NULL)

    unless $?.success?
      warn "Warning: YJIT wrapper script not found at #{wrapper_path}"
    end
  end

  def extract_yjit_stats_from_output(output)
    return nil if output.nil? || output.empty?

    if ENV['DEBUG_YJIT_STATS']
      warn "===DEBUG: Attempting to extract YJIT stats from output"
      warn "===DEBUG: Output length: #{output.length} chars"
      warn "===DEBUG: Contains START marker: #{output.include?('===YJIT_STATS_START===')}"
      warn "===DEBUG: Contains END marker: #{output.include?('===YJIT_STATS_END===')}"
    end

    # Look for stats markers in the output
    if output =~ /===YJIT_STATS_START===\n(.*?)\n===YJIT_STATS_END===/m
      stats_json = $1

      if ENV['DEBUG_YJIT_STATS']
        warn "===DEBUG: Found stats JSON, length: #{stats_json.length} chars"
        warn "===DEBUG: First 100 chars: #{stats_json[0..99]}"
      end

      begin
        parsed = JSON.parse(stats_json)
        if ENV['DEBUG_YJIT_STATS']
          warn "===DEBUG: Successfully parsed JSON with #{parsed.keys.size} keys"
          warn "===DEBUG: Keys include: #{parsed.keys.first(10).join(', ')}..."
        end
        return parsed
      rescue JSON::ParserError => e
        warn "ERROR: Failed to parse YJIT stats JSON: #{e.message}"
        warn "Stats JSON (first 500 chars): #{stats_json[0..499]}"
        if ENV['DEBUG_YJIT_STATS']
          warn "===DEBUG: Full JSON string:"
          warn stats_json
        end
      end
    elsif ENV['DEBUG_YJIT_STATS']
      warn "===DEBUG: No stats markers found in output"
      warn "===DEBUG: First 500 chars of output:"
      warn output[0..499]
    end

    # Check for error markers
    if output =~ /===YJIT_STATS_ERROR===\n(.*?)\n===YJIT_STATS_ERROR_END===/m
      warn "YJIT stats collection reported error: #{$1}"
    end

    nil
  end


end

# Parse command-line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] [benchmark_name ...]"

  opts.on('--yjit-stats', 'Collect YJIT statistics for benchmark runs') do
    options[:collect_yjit_stats] = true
  end

  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

# Initialize benchmark runner with options
yjit_bench = YJITBench.new(collect_yjit_stats: options[:collect_yjit_stats])
at_exit { yjit_bench.shutdown }

if ARGV.empty?
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
  benchmarks = ARGV
  benchmarks.each do |benchmark|
    yjit_bench.run_benchmark(benchmark)
  end
end
