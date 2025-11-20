# frozen_string_literal: true

module YJITStatsProcessor
  class << self
    # Process raw YJIT stats and extract essential metrics
    def process_stats(raw_stats)
      return nil if raw_stats.nil? || raw_stats['error']

      # Validate stats structure
      unless validate_stats(raw_stats)
        warn "YJIT stats validation failed - stats may be empty or invalid"
        return nil
      end

      # Calculate derived metrics
      side_exits = calculate_side_exits(raw_stats)
      total_exits = side_exits + (raw_stats['leave_interp_return'] || 0)

      # Handle both old and new stat field names
      exec_instruction = raw_stats['exec_instruction'] || raw_stats['yjit_insns_count'] || 0
      vm_insns_count = raw_stats['vm_insns_count'] || 0

      # Calculate key performance metrics
      retired_in_yjit = exec_instruction - side_exits
      total_insns_count = retired_in_yjit + vm_insns_count

      ratio_in_yjit = if total_insns_count > 0
        100.0 * retired_in_yjit.to_f / total_insns_count
      else
        0.0
      end

      avg_len_in_yjit = if total_exits > 0
        retired_in_yjit.to_f / total_exits
      else
        0.0
      end

      # Calculate invalidation ratio
      invalidation_count = raw_stats['invalidation_count'] || 0
      compiled_block_count = raw_stats['compiled_block_count'] || 0
      invalidation_ratio = if compiled_block_count > 0
        100.0 * invalidation_count.to_f / compiled_block_count
      else
        0.0
      end

      # Log debug info if requested
      log_debug_info(raw_stats) if ENV['DEBUG_YJIT_STATS']

      # Extract essential metrics for storage
      {
        # Key performance metrics
        ratio_in_yjit: ratio_in_yjit.round(2),
        avg_len_in_yjit: avg_len_in_yjit.round(1),

        # Code generation metrics
        inline_code_size: raw_stats['inline_code_size'] || 0,
        outlined_code_size: raw_stats['outlined_code_size'] || 0,

        # Compilation metrics
        compiled_iseq_count: raw_stats['compiled_iseq_count'] || 0,
        compiled_block_count: compiled_block_count,
        invalidation_count: invalidation_count,
        invalidation_ratio: invalidation_ratio.round(2),

        # Resource metrics
        binding_allocations: raw_stats['binding_allocations'] || 0,
        binding_set: raw_stats['binding_set'] || 0,
        constant_state_bumps: raw_stats['constant_state_bumps'] || 0,
        compile_time_ms: ((raw_stats['compile_time_ns'] || 0) / 1_000_000.0).round(1),

        # Exit summary
        side_exits_total: side_exits,
        total_exits: total_exits,

        # Top exit reasons (for analysis)
        top_exit_reasons: extract_top_exits(raw_stats, limit: 20)
      }
    end


    private

    # Validate that stats contain expected fields and reasonable values
    def validate_stats(stats)
      return false unless stats.is_a?(Hash)

      # Check for essential fields that indicate real stats
      # If these are all zero/missing, stats weren't actually collected
      essential_indicators = [
        stats['exec_instruction'] || stats['yjit_insns_count'],
        stats['compiled_iseq_count'],
        stats['compiled_block_count']
      ].compact

      return false if essential_indicators.empty?
      return false if essential_indicators.all? { |v| v == 0 }

      # Validate numeric fields are reasonable
      if stats['ratio_in_yjit'] && (stats['ratio_in_yjit'] < 0 || stats['ratio_in_yjit'] > 100)
        warn "Invalid ratio_in_yjit value: #{stats['ratio_in_yjit']}"
        return false
      end

      true
    end

    # Calculate total side exits (all exit_* counters)
    def calculate_side_exits(stats)
      stats.select { |k, _| k.to_s.start_with?('exit_') }
           .values
           .select { |v| v.is_a?(Numeric) }
           .sum
    end

    # Extract top N exit reasons
    def extract_top_exits(stats, limit: 20)
      exits = []

      stats.each do |key, value|
        # Collect all exit-related counters
        if key.to_s.match?(/^(exit_|send_|leave_|getivar_|setivar_|oaref_)/) && value.is_a?(Numeric) && value > 0
          exits << [key.to_s, value]
        end
      end

      # Sort by count (descending) and take top N
      exits.sort_by { |_, count| -count }
           .first(limit)
           .to_h
    end

    # Log debug information about stats
    def log_debug_info(stats)
      warn "=== YJIT Stats Debug Info ==="
      warn "Total keys: #{stats.keys.size}"
      warn "exec_instruction: #{stats['exec_instruction']}"
      warn "yjit_insns_count: #{stats['yjit_insns_count']}"
      warn "compiled_iseq_count: #{stats['compiled_iseq_count']}"
      warn "compiled_block_count: #{stats['compiled_block_count']}"
      warn "exit counter keys: #{stats.keys.select { |k| k.start_with?('exit_') }.size}"
      warn "============================="
    end
  end
end