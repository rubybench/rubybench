#!/usr/bin/env ruby
# frozen_string_literal: true

# YJIT Stats Collection Wrapper
# This script wraps the benchmark runner to collect YJIT statistics
# from the actual benchmark process, not a separate Ruby instance.

require 'json'

# Enable YJIT stats collection if available
if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable_stats)
  RubyVM::YJIT.enable_stats

  # Register exit handler to output stats after benchmark completes
  at_exit do
    # Only output stats if YJIT is enabled and has stats
    if RubyVM::YJIT.respond_to?(:runtime_stats)
      begin
        stats = RubyVM::YJIT.runtime_stats

        # Output stats with clear markers for parsing
        # Use STDERR to avoid interfering with benchmark output
        $stderr.puts "\n===YJIT_STATS_START==="
        $stderr.puts JSON.generate(stats)
        $stderr.puts "===YJIT_STATS_END==="
        $stderr.flush
      rescue => e
        $stderr.puts "===YJIT_STATS_ERROR==="
        $stderr.puts "Failed to collect YJIT stats: #{e.message}"
        $stderr.puts "===YJIT_STATS_ERROR_END==="
      end
    end
  end
end

# The wrapper is called with the same arguments as run_benchmarks.rb would receive
# e.g., ruby wrapper.rb benchmark_name [options]
# We need to preserve these for run_benchmarks.rb

# Debug output to understand what we're receiving
if ENV['DEBUG_YJIT_STATS']
  $stderr.puts "===DEBUG: Wrapper ARGV: #{ARGV.inspect}"
  $stderr.puts "===DEBUG: Working directory: #{Dir.pwd}"
end

# Load and execute the actual benchmark runner
# ARGV is already set correctly - run_benchmarks.rb will use it as-is
begin
  load './run_benchmarks.rb'
rescue LoadError => e
  $stderr.puts "ERROR: Could not load run_benchmarks.rb: #{e.message}"
  $stderr.puts "Working directory: #{Dir.pwd}"
  $stderr.puts "Files in current directory: #{Dir.entries('.').select { |f| f.end_with?('.rb') }.join(', ')}"
  $stderr.puts "ARGV was: #{ARGV.inspect}"
  exit 1
rescue => e
  $stderr.puts "ERROR: Failed to run benchmark: #{e.class}: #{e.message}"
  $stderr.puts e.backtrace.join("\n")
  exit 1
end