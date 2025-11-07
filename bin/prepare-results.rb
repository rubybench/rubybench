#!/usr/bin/env ruby

require 'fileutils'

repo_url = ENV['RUBYBENCH_RESULTS_REPO']
branch = ENV.fetch('RUBYBENCH_RESULTS_BRANCH', 'main')
results_dir = File.expand_path('../results', __dir__)

unless repo_url
  puts "RUBYBENCH_RESULTS_REPO not set, skipping results preparation"
  exit 0
end

if File.exist?("#{results_dir}/.git")
  # Repository exists - fetch and reset to origin
  puts "Updating existing results repository"
  Dir.chdir(results_dir) do
    system("git", "fetch", "origin", exception: true)
    system("git", "checkout", branch, exception: true)
    system("git", "reset", "--hard", "origin/#{branch}", exception: true)
    system("git", "clean", "-fd", exception: true)
  end
else
  # No repo - clean up any non-git results and clone
  FileUtils.rm_rf(results_dir) if File.exist?(results_dir)
  puts "Cloning #{repo_url} into results/"
  system("git", "clone", "--branch", branch, repo_url, results_dir, exception: true)
end

puts "Results repository prepared"