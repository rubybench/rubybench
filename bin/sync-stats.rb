#!/usr/bin/env ruby

require 'fileutils'

class StatsSyncer
  def initialize
    @repo_url = ENV['RUBYBENCH_STATS_REPO']
    @branch = ENV.fetch('RUBYBENCH_STATS_BRANCH', 'master')
    @stats_dir = ENV.fetch('RUBYBENCH_STATS_DIR', File.expand_path('../../rubybench-stats', __dir__))
    @commit_prefix = ENV.fetch('RUBYBENCH_RESULTS_COMMIT_PREFIX', '')
  end

  def sync!
    return puts("RUBYBENCH_STATS_REPO not set, skipping stats sync") unless @repo_url
    return puts("Stats directory not found") unless Dir.exist?(@stats_dir)
    return puts("Stats is not a git repository") unless Dir.exist?("#{@stats_dir}/.git")

    Dir.chdir(@stats_dir) do
      # Check for changes
      if `git status --porcelain`.empty?
        puts "No stats changes to sync"
        return
      end

      # Commit and push
      system("git", "add", "-A")
      system("git", "commit", "-m", "#{@commit_prefix}Sync ZJIT stats".strip)
      system("git", "push", "origin", @branch)

      puts "Stats pushed"
    end
  end
end

StatsSyncer.new.sync!
