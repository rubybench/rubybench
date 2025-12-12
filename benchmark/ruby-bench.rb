#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require_relative '../lib/ruby_bench'

RUBIES_PATH = File.expand_path('../results/rubies.yml', __dir__)

options = { results_root: "results" }
OptionParser.new do |parser|
  parser.on("--results-root [ROOT]", "A directory in which the results tree will be output") do |path|
    options[:results_root] = path
  end
end.parse!

runner = RubyBench::DockerRunner.new(rubies_path: RUBIES_PATH)
ruby_bench = RubyBench.new(runner: runner, results_root: options[:results_root])

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
