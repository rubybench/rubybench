#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/yjit_stats_processor'
require_relative '../lib/exit_report_formatter'

class TestYJITStats < Minitest::Test
  def setup
    # Sample YJIT stats data based on actual structure
    @sample_stats = {
      'exec_instruction' => 1000000,
      'yjit_insns_count' => 1000000,  # Alternative name
      'vm_insns_count' => 10000,
      'leave_interp_return' => 500,
      'inline_code_size' => 5242880,
      'outlined_code_size' => 524288,
      'compiled_iseq_count' => 1234,
      'compiled_block_count' => 5678,
      'invalidation_count' => 100,
      'binding_allocations' => 890,
      'binding_set' => 567,
      'constant_state_bumps' => 45,
      'compile_time_ns' => 234567890,

      # Exit counters
      'exit_send_missing_method' => 234,
      'exit_send_refined_method' => 123,
      'exit_leave_se_interrupt' => 89,
      'send_missing_method' => 100,
      'leave_se_interrupt' => 50,
      'getivar_megamorphic' => 30,
      'setivar_frozen' => 10,
      'oaref_not_array' => 20
    }
  end

  def test_process_stats_calculates_ratio_in_yjit
    result = YJITStatsProcessor.process_stats(@sample_stats)

    assert_not_nil result
    assert_in_delta 98.0, result[:ratio_in_yjit], 1.0
  end

  def test_process_stats_calculates_avg_len_in_yjit
    result = YJITStatsProcessor.process_stats(@sample_stats)

    assert_not_nil result
    assert_operator result[:avg_len_in_yjit], :>, 100
  end

  def test_process_stats_calculates_invalidation_ratio
    result = YJITStatsProcessor.process_stats(@sample_stats)

    assert_not_nil result
    assert_in_delta 1.76, result[:invalidation_ratio], 0.1
  end

  def test_process_stats_extracts_essential_metrics
    result = YJITStatsProcessor.process_stats(@sample_stats)

    assert_equal 5242880, result[:inline_code_size]
    assert_equal 524288, result[:outlined_code_size]
    assert_equal 1234, result[:compiled_iseq_count]
    assert_equal 5678, result[:compiled_block_count]
    assert_equal 100, result[:invalidation_count]
    assert_equal 890, result[:binding_allocations]
    assert_equal 567, result[:binding_set]
    assert_equal 45, result[:constant_state_bumps]
    assert_in_delta 234.6, result[:compile_time_ms], 0.1
  end

  def test_process_stats_extracts_top_exits
    result = YJITStatsProcessor.process_stats(@sample_stats)

    assert_not_nil result[:top_exit_reasons]
    assert_operator result[:top_exit_reasons].size, :<=, 5
    assert_includes result[:top_exit_reasons].keys, 'exit_send_missing_method'
  end

  def test_process_stats_handles_missing_fields
    minimal_stats = {
      'exec_instruction' => 1000,
      'vm_insns_count' => 100
    }

    result = YJITStatsProcessor.process_stats(minimal_stats)

    assert_not_nil result
    assert_equal 0, result[:inline_code_size]
    assert_equal 0, result[:compiled_iseq_count]
    assert_equal 0.0, result[:compile_time_ms]
  end

  def test_process_stats_handles_nil_input
    result = YJITStatsProcessor.process_stats(nil)
    assert_nil result
  end

  def test_process_stats_handles_error_response
    error_stats = { 'error' => 'YJIT stats not available' }
    result = YJITStatsProcessor.process_stats(error_stats)
    assert_nil result
  end

  def test_extract_full_stats_for_report
    result = YJITStatsProcessor.extract_full_stats_for_report(@sample_stats)

    assert_not_nil result
    assert_not_nil result[:send_exits]
    assert_not_nil result[:leave_exits]
    assert_not_nil result[:exit_exits]
    assert_includes result[:send_exits], 'missing_method'
    assert_equal 100, result[:send_exits]['missing_method']
  end

  def test_exit_report_formatter_generates_report
    stats = YJITStatsProcessor.extract_full_stats_for_report(@sample_stats)
    report = ExitReportFormatter.generate_report('test_benchmark', '20250115', 'abc123def', stats)

    assert_not_nil report
    assert_includes report, 'YJIT Exit Report'
    assert_includes report, 'test_benchmark'
    assert_includes report, '20250115'
    assert_includes report, 'ratio_in_yjit'
    assert_includes report, 'Code Generation'
    assert_includes report, 'Compilation Statistics'
  end

  def test_exit_report_formatter_handles_nil_stats
    report = ExitReportFormatter.generate_report('test_benchmark', '20250115', 'abc123def', nil)

    assert_not_nil report
    assert_includes report, 'No stats available'
  end

  def test_side_exits_calculation
    result = YJITStatsProcessor.process_stats(@sample_stats)

    # Sum of all exit_* counters
    expected_side_exits = 234 + 123 + 89  # exit_send_missing_method + exit_send_refined_method + exit_leave_se_interrupt
    assert_equal expected_side_exits, result[:side_exits_total]
  end

  def test_total_exits_calculation
    result = YJITStatsProcessor.process_stats(@sample_stats)

    side_exits = 234 + 123 + 89
    total_exits = side_exits + 500  # + leave_interp_return
    assert_equal total_exits, result[:total_exits]
  end
end