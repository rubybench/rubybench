#!/usr/bin/env ruby
require 'yaml'

rubies = YAML.load_file(File.expand_path('../rubies.yml', __dir__))
benchmarks = YAML.load_file(File.expand_path('../benchmark/yjit-bench/benchmarks.yml', __dir__), symbolize_names: true)
benchmark_results = benchmarks.map do |benchmark, _|
  [benchmark, YAML.load_file(File.expand_path("../results/yjit-bench/#{benchmark}.yml", __dir__))]
end.to_h

ruby = rubies.keys.select { |ruby| benchmark_results.first.last.key?(ruby) }.max
dashboard = {
  date: rubies[ruby].match(/ruby [^ ]+ \(([^)T ]+)/)[1],
  headline: {
    no_jit: [],
    yjit: [],
    rjit: [],
    benchmarks: [],
  },
  other: {
    no_jit: [],
    yjit: [],
    rjit: [],
    benchmarks: [],
  },
  micro: {
    no_jit: [],
    yjit: [],
    rjit: [],
    benchmarks: [],
  },
}

def format_float(float)
  ('%0.2f' % float).to_f
end

benchmarks.sort_by(&:first).each do |benchmark, metadata|
  results = benchmark_results.fetch(benchmark)
  category = metadata.fetch(:category, 'other').to_sym

  no_jit, yjit, rjit = results[ruby]
  if no_jit
    dashboard[category][:no_jit] << format_float(no_jit / no_jit)
    dashboard[category][:yjit] << (yjit ? format_float(no_jit / yjit) : 0.0)
    dashboard[category][:rjit] << (rjit ? format_float(no_jit / rjit) : 0.0)
    dashboard[category][:benchmarks] << benchmark.to_s
  end
end

dashboard = dashboard.transform_keys(&:to_s).transform_values do |value|
  value.is_a?(Hash) ? value.transform_keys(&:to_s) : value
end
File.write(File.expand_path('../results/dashboard.yml', __dir__), dashboard.to_yaml)
