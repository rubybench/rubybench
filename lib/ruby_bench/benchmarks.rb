# frozen_string_literal: true

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

      conflicts = @ractor_compatible & @ractor_only
      if conflicts.any?
        puts "NOTE: Found benchmarks with same name in both regular and ractor-only: #{conflicts.join(', ')}"
        puts "      These will be saved with 'ractor_only_' prefix for ractor-only versions."
      end

      self
    end
  end
end
