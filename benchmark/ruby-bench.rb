#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative '../lib/ruby_bench'
require_relative '../lib/ruby_bench/machine'

RUBIES_PATH = File.expand_path('../results/rubies.yml', __dir__)

options = { results_root: "results" }
OptionParser.new do |parser|
  parser.on("--results-root [ROOT]", "A directory in which the results tree will be output") do |path|
    options[:results_root] = path
  end
  parser.on("--ruby PATH", "Path to Ruby binary (bypasses Docker)") do |path|
    options[:ruby_binary] = path
  end
  parser.on("--date DATE", "Target date for results (required with --ruby, format: YYYYMMDD)") do |date|
    options[:target_date] = date.to_i
  end
end.parse!

if options[:ruby_binary] && !options[:target_date]
  abort "ERROR: --date is required when using --ruby"
end
if options[:target_date] && !options[:ruby_binary]
  abort "ERROR: --ruby is required when using --date"
end

machine_results_root = "#{options[:results_root]}/#{RubyBench::Machine.path}"

runner = if options[:ruby_binary]
  RubyBench::LocalRunner.new(ruby_binary: options[:ruby_binary], target_date: options[:target_date])
else
  unless File.exist?(RUBIES_PATH)
    abort "ERROR: rubies.yml not found at #{RUBIES_PATH}. Please setup using bin/prepare-results.rb"
  end
  RubyBench::DockerRunner.new(rubies_path: RUBIES_PATH)
end

ruby_bench = RubyBench.new(runner: runner, results_root: machine_results_root)
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
