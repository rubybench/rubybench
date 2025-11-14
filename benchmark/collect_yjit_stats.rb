#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal script to collect YJIT runtime stats
# This runs inside the Docker container after benchmark execution
# Outputs JSON to stdout for the runner to capture

require 'json'

# Check if YJIT is enabled and stats are available
unless defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:runtime_stats)
  puts JSON.generate({ error: "YJIT stats not available" })
  exit 1
end

begin
  # Collect raw stats
  stats = RubyVM::YJIT.runtime_stats

  # Add a flag to indicate successful collection
  stats[:stats_collected] = true
  stats[:collection_time] = Time.now.to_s

  # Output as JSON
  puts JSON.generate(stats)
rescue => e
  puts JSON.generate({
    error: "Failed to collect YJIT stats",
    message: e.message,
    backtrace: e.backtrace.first(5)
  })
  exit 1
end