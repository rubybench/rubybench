# frozen_string_literal: true

class RubyBench
  class Benchmarks
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
      @ractor_only = @benchmarks_yml.select { |_, info| info['ractor_only'] == true }.keys
      @regular = @benchmarks_yml.keys - @ractor_only
      self
    end
  end
end
