#!/usr/bin/env ruby

require 'fileutils'

class ResultSyncer
  def initialize(result_type = nil)
    @repo_url = ENV['RUBYBENCH_RESULTS_REPO']
    @branch = ENV.fetch('RUBYBENCH_RESULTS_BRANCH', 'main')
    @results_dir = File.expand_path('../results', __dir__)
    @commit_prefix = ENV.fetch('RUBYBENCH_RESULTS_COMMIT_PREFIX', '')
    @result_type = result_type
  end

  def sync!
    return puts("RUBYBENCH_RESULTS_REPO not set, skipping result sync") unless @repo_url
    return puts("Results directory not found") unless Dir.exist?(@results_dir)
    return puts("Results is not a git repository") unless Dir.exist?("#{@results_dir}/.git")

    Dir.chdir(@results_dir) do
      # Check for changes
      if `git status --porcelain`.empty?
        puts "No changes to sync"
        return
      end

      # Commit and push
      system("git", "add", "-A")
      system("git", "commit", "-m", build_commit_message)
      system("git", "push", "origin", @branch)

      puts "Results pushed"
    end
  end

  private

  def build_commit_message
    message = case @result_type
    when 'ruby-bench'
      "Sync ruby-bench results"
    when 'ruby'
      "Sync ruby/ruby benchmark results"
    else
      "Sync benchmark results"
    end
    "#{@commit_prefix}#{message}".strip
  end
end

# Accept optional argument for result type (ruby-bench or ruby)
result_type = ARGV[0]

# Validate result type if provided
if result_type && !['ruby-bench', 'ruby'].include?(result_type)
  $stderr.puts "ERROR: Invalid result type '#{result_type}'"
  $stderr.puts "Valid options are: ruby-bench, ruby"
  exit 1
end

ResultSyncer.new(result_type).sync!
