# frozen_string_literal: true

class RubyBench
  class LocalRunner < Runner
    def initialize(ruby_binary:, target_date:)
      @ruby_binary = ruby_binary
      @target_date = target_date
    end

    def next_target_date(_existing_results)
      @target_date
    end

    def latest_date
      @target_date
    end

    def execute_zjit_stats(benchmark)
      env = "env BUNDLE_JOBS=8"
      ruby_opts = "#{@ruby_binary} --zjit-stats"
      cmd = [
        'bash', '-c',
        "cd benchmark/ruby-bench && #{env} ./run_benchmarks.rb #{benchmark} --once --out-name zjit_stats_temp -e 'ruby::#{ruby_opts}'",
      ]
      IO.popen(cmd, &:read)
    end

    def execute(benchmark, opts:, category:, no_pinning:)
      env = "env BUNDLE_JOBS=8"
      category_arg = category ? "--category #{category}" : ""
      pinning_arg = no_pinning ? "--no-pinning" : ""
      ruby_opts = opts ? "#{@ruby_binary} #{opts}" : @ruby_binary
      cmd = [
        'bash', '-c',
        "cd benchmark/ruby-bench && #{env} ./run_benchmarks.rb #{benchmark} #{category_arg} #{pinning_arg} -e 'ruby::#{ruby_opts}'",
      ]
      IO.popen(cmd, &:read)
    end
  end
end
