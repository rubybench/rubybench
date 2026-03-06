#!/usr/bin/env ruby

require 'fileutils'

repo_url = ENV['RUBYBENCH_STATS_REPO']
branch = ENV.fetch('RUBYBENCH_STATS_BRANCH', 'master')
stats_dir = ENV.fetch('RUBYBENCH_STATS_DIR', File.expand_path('../../rubybench-stats', __dir__))

unless repo_url
  puts "RUBYBENCH_STATS_REPO not set, skipping stats preparation"
  exit 0
end

if File.exist?("#{stats_dir}/.git")
  # Repository exists - fetch and reset to origin
  puts "Updating existing stats repository"
  Dir.chdir(stats_dir) do
    system("git", "fetch", "origin", exception: true)
    system("git", "checkout", branch, exception: true)
    system("git", "reset", "--hard", "origin/#{branch}", exception: true)
    system("git", "clean", "-fd", exception: true)
  end
else
  # No repo - clean up any non-git directory and clone
  FileUtils.rm_rf(stats_dir) if File.exist?(stats_dir)
  puts "Cloning #{repo_url} into #{stats_dir}"
  system("git", "clone", "--branch", branch, repo_url, stats_dir, exception: true)
end

puts "Stats repository prepared"
