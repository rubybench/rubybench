# frozen_string_literal: true

module ExitReportFormatter
  class << self
    # Generate a text exit report from processed stats
    def generate_report(benchmark_name, date, ruby_sha, stats)
      return "No stats available for #{benchmark_name}" if stats.nil?

      report = []

      # Header
      report << "=" * 70
      report << "YJIT Exit Report"
      report << "=" * 70
      report << "Benchmark: #{benchmark_name}"
      report << "Date: #{date}"
      report << "Ruby: #{ruby_sha[0..9] if ruby_sha}" if ruby_sha
      report << "=" * 70
      report << ""

      # Key Performance Metrics
      report << "YJIT Performance Metrics:"
      report << "-" * 40
      report << format_metric("ratio_in_yjit", stats[:ratio_in_yjit], "%")
      report << format_metric("avg_len_in_yjit", stats[:avg_len_in_yjit])
      report << ""

      # Code Generation
      report << "Code Generation:"
      report << "-" * 40
      report << format_metric("inline_code_size", format_bytes(stats[:inline_code_size]))
      report << format_metric("outlined_code_size", format_bytes(stats[:outlined_code_size]))
      report << ""

      # Compilation Statistics
      report << "Compilation Statistics:"
      report << "-" * 40
      report << format_metric("compiled_iseq_count", stats[:compiled_iseq_count])
      report << format_metric("compiled_block_count", stats[:compiled_block_count])
      report << format_metric("invalidation_count", stats[:invalidation_count])
      report << format_metric("invalidation_ratio", stats[:invalidation_ratio], "%")
      report << format_metric("compile_time_ms", stats[:compile_time_ms])
      report << ""

      # Resource Usage
      report << "Resource Usage:"
      report << "-" * 40
      report << format_metric("binding_allocations", stats[:binding_allocations])
      report << format_metric("binding_set", stats[:binding_set])
      report << format_metric("constant_state_bumps", stats[:constant_state_bumps])
      report << ""

      # Exit Statistics
      report << "Exit Statistics:"
      report << "-" * 40
      report << format_metric("side_exits_total", stats[:side_exits_total])
      report << format_metric("total_exits", stats[:total_exits])

      if stats[:total_insns_count]
        report << format_metric("total_insns_count", stats[:total_insns_count])
        report << format_metric("vm_insns_count", stats[:vm_insns_count])
        report << format_metric("yjit_insns_count", stats[:yjit_insns_count])
      end
      report << ""

      # Exit breakdown by category (if available)
      if stats[:send_exits] && !stats[:send_exits].empty?
        report << format_exit_section("Method call exit reasons", stats[:send_exits], stats[:side_exits_total])
        report << ""
      end

      if stats[:leave_exits] && !stats[:leave_exits].empty?
        report << format_exit_section("Leave exit reasons", stats[:leave_exits], stats[:side_exits_total])
        report << ""
      end

      if stats[:getivar_exits] && !stats[:getivar_exits].empty?
        report << format_exit_section("Instance variable get exit reasons", stats[:getivar_exits], stats[:side_exits_total])
        report << ""
      end

      if stats[:setivar_exits] && !stats[:setivar_exits].empty?
        report << format_exit_section("Instance variable set exit reasons", stats[:setivar_exits], stats[:side_exits_total])
        report << ""
      end

      if stats[:oaref_exits] && !stats[:oaref_exits].empty?
        report << format_exit_section("Optimized array ref exit reasons", stats[:oaref_exits], stats[:side_exits_total])
        report << ""
      end

      # Top exits overall
      if stats[:exit_exits] && !stats[:exit_exits].empty?
        report << format_top_exits(stats[:exit_exits], stats[:side_exits_total])
        report << ""
      elsif stats[:top_exit_reasons] && !stats[:top_exit_reasons].empty?
        # Fallback to simplified top exits if we don't have full breakdown
        report << "Top Exit Reasons:"
        report << "-" * 40
        stats[:top_exit_reasons].each do |reason, count|
          pct = (100.0 * count / stats[:side_exits_total]).round(1) if stats[:side_exits_total] > 0
          report << sprintf("  %-30s %10d (%5.1f%%)", reason, count, pct || 0)
        end
        report << ""
      end

      report.join("\n")
    end

    private

    def format_metric(name, value, suffix = nil)
      formatted_name = name.to_s.gsub('_', ' ')
      if suffix
        sprintf("  %-30s %15s%s", formatted_name + ":", value, suffix)
      else
        sprintf("  %-30s %15s", formatted_name + ":", value)
      end
    end

    def format_bytes(bytes)
      return "0 B" if bytes.nil? || bytes == 0

      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)} KB"
      else
        "#{(bytes / (1024.0 * 1024.0)).round(1)} MB"
      end
    end

    def format_exit_section(title, exits, total_exits)
      lines = []
      lines << title + ":"

      # Calculate section total
      section_total = exits.values.sum
      section_pct = (100.0 * section_total / total_exits).round(1) if total_exits > 0

      # Find longest name for alignment
      max_name_len = exits.keys.map(&:length).max || 20
      max_name_len = [max_name_len, 30].min # Cap at 30 for readability

      exits.each do |name, count|
        pct = (100.0 * count / total_exits).round(1) if total_exits > 0
        lines << sprintf("  %-#{max_name_len}s %10d (%5.1f%%)", name, count, pct || 0)
      end

      lines << sprintf("  %-#{max_name_len}s %10d (%5.1f%%)", "[Total #{title.downcase}]", section_total, section_pct || 0)

      lines.join("\n")
    end

    def format_top_exits(exits, total_exits, limit = 20)
      lines = []

      # Take top N exits
      top_exits = exits.first(limit)
      top_total = top_exits.values.sum
      top_pct = (100.0 * top_total / total_exits).round(1) if total_exits > 0

      lines << "Top #{[exits.size, limit].min} Most Frequent Exit Operations (#{top_pct}% of all exits):"
      lines << "-" * 60

      # Find longest name for alignment
      max_name_len = top_exits.keys.map(&:to_s.length).max || 20
      max_name_len = [max_name_len, 35].min

      top_exits.each do |name, count|
        pct = (100.0 * count / total_exits).round(1) if total_exits > 0
        lines << sprintf("  %-#{max_name_len}s %10d (%5.1f%%)", name, count, pct || 0)
      end

      lines.join("\n")
    end
  end
end