# frozen_string_literal: true

class RubyBench
  class Runner
    def next_target_date(existing_results)
      raise NotImplementedError
    end

    def execute(benchmark, opts:, category:, no_pinning:)
      raise NotImplementedError
    end

    def execute_zjit_stats(benchmark)
      raise NotImplementedError
    end

    def latest_date
      raise NotImplementedError
    end

    def setup_for_date(target_date)
    end

    def cleanup_after_benchmark
    end

    def shutdown
    end
  end
end
