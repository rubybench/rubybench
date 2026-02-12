# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

class RubyBench
  RACTOR_ITERATION_PATTERN = /^\s*(\d+)\s+#\d+:\s*(\d+)ms/
  RSS_PATTERN = /^RSS:\s*([\d.]+)MiB/

  def initialize(runner:, results_root: "results")
    @runner = runner
    @results_root = results_root
  end

  def run_benchmark(benchmark)
    results_file = "#{@results_root}/ruby-bench/#{benchmark}.yml"
    rss_file = "#{@results_root}/ruby-bench-rss/#{benchmark}.yml"
    run_benchmark_generic(benchmark, results_file, rss_file: rss_file, is_ractor: false)
  end

  ZJIT_STATS_JSON_PATH = 'benchmark/ruby-bench/zjit_stats_temp.json'

  def run_zjit_stats(benchmark, stats_dir:)
    stats_file = "#{stats_dir}/ruby-bench/zjit/#{benchmark}.txt"

    out = @runner.execute_zjit_stats(benchmark)
    puts out if out

    stats_string = read_zjit_stats_string
    if stats_string
      FileUtils.mkdir_p(File.dirname(stats_file))
      File.write(stats_file, stats_string)
      puts "Wrote ZJIT stats for #{benchmark}"
    else
      puts "ZJIT stats_string not found for #{benchmark}"
    end

    @runner.cleanup_after_benchmark
  end

  def run_ractor_benchmark(benchmark, ractor_only: false)
    safe_name = benchmark.gsub('/', '_')
    prefix = ractor_only ? "ractor_only_" : ""
    category = ractor_only ? 'ractor-only' : 'ractor'
    results_file = "#{@results_root}/ruby-bench-ractor/#{prefix}#{safe_name}.yml"
    rss_file = "#{@results_root}/ruby-bench-ractor-rss/#{prefix}#{safe_name}.yml"

    run_benchmark_generic(benchmark, results_file,
      rss_file: rss_file,
      is_ractor: true,
      category: category,
      label: "ractor:#{benchmark}",
      no_pinning: true
    )
  end

  def shutdown
    @runner.shutdown
  end

  private

  def run_benchmark_generic(benchmark, results_file, rss_file: nil, is_ractor: false, category: nil, label: nil, no_pinning: false)
    results = File.exist?(results_file) ? YAML.load_file(results_file) : {}
    rss_results = (rss_file && File.exist?(rss_file)) ? YAML.load_file(rss_file) : {}

    target_date = @runner.next_target_date(results)
    if target_date.nil?
      message = "Every Ruby version is already benchmarked"
      message += " for #{label}" if label
      puts message
      return
    end

    prefix = label ? "#{label} " : ""
    puts "#{prefix}target_date: #{target_date}"

    @runner.setup_for_date(target_date)
    result = is_ractor ? {} : []
    rss_result = []

    [nil, '--yjit', '--zjit'].each do |opts|
      out = @runner.execute(benchmark, opts: opts, category: category, no_pinning: no_pinning)
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
    write_results(results_file, results)

    if rss_file
      rss_results[target_date] = rss_result
      write_results(rss_file, rss_results)
    end

    @runner.cleanup_after_benchmark
  end

  def write_results(file_path, results)
    FileUtils.mkdir_p(File.dirname(file_path))
    File.open(file_path, "w") do |io|
      results.sort_by(&:first).each do |date, values|
        io.puts "#{date}: #{values.to_json}"
      end
    end
  end

  def read_zjit_stats_string
    return nil unless File.exist?(ZJIT_STATS_JSON_PATH)
    data = JSON.parse(File.read(ZJIT_STATS_JSON_PATH))
    data["raw_data"]&.each_value do |benchmarks|
      benchmarks.each_value do |bench_data|
        return bench_data["zjit_stats_string"] if bench_data.is_a?(Hash) && bench_data["zjit_stats_string"]
      end
    end
    nil
  rescue JSON::ParserError
    nil
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
end

require_relative 'ruby_bench/benchmarks'
require_relative 'ruby_bench/runner'
require_relative 'ruby_bench/docker_runner'
