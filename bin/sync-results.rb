#!/usr/bin/env ruby

require 'fileutils'
require 'tmpdir'
require 'time'
require 'yaml'

class ResultSyncer
  def initialize
    @repo_url = ENV['RUBYBENCH_RESULTS_REPO']
    @branch = ENV.fetch('RUBYBENCH_RESULTS_BRANCH', 'main')
    @local_path = ENV.fetch('RUBYBENCH_RESULTS_PATH', File.join(Dir.tmpdir, 'rubybench-results'))
    @commit_prefix = ENV.fetch('RUBYBENCH_RESULTS_COMMIT_PREFIX', '')
    @source_dir = File.expand_path('../results', __dir__)
  end

  def sync!
    return puts("RUBYBENCH_RESULTS_REPO not set, skipping result sync") unless @repo_url

    prepare_repository
    sync_files
    commit_and_push if changes_present?
  end

  private

  def prepare_repository
    repo_exists? ? pull_latest : clone_repository
  end

  def repo_exists?
    File.exist?(File.join(@local_path, '.git'))
  end

  def clone_repository
    FileUtils.mkdir_p(File.dirname(@local_path))

    git("clone", "--branch", @branch, @repo_url, @local_path) ||
      begin
        FileUtils.rm_rf(@local_path)
        git!("clone", @repo_url, @local_path)
        create_branch unless default_branch?
      end
  end

  def pull_latest
    in_repo do
      git("fetch", "origin")

      if remote_branch_exists?
        git("checkout", @branch)
        git("reset", "--hard", "origin/#{@branch}")
      else
        create_branch
      end
    end
  end

  def create_branch
    in_repo { git("checkout", "-b", @branch) }
  end

  def remote_branch_exists?
    in_repo { git("show-ref", "--verify", "refs/remotes/origin/#{@branch}", silent: true) }
  end

  def default_branch?
    %w[main master].include?(@branch)
  end

  def sync_files
    return warn("No results directory found") unless Dir.exist?(@source_dir)

    target = File.join(@local_path, 'results')
    FileUtils.mkdir_p(target)

    rsync_available? ? rsync_files(target) : copy_files(target)
  end

  def rsync_available?
    system("which", "rsync")
  end

  def rsync_files(target)
    system("rsync", "-a", "--delete", "#{@source_dir}/", "#{target}/")
  end

  def copy_files(target)
    FileUtils.rm_rf(Dir.glob("#{target}/*"), secure: true)
    FileUtils.cp_r(Dir.glob("#{@source_dir}/*"), target)
  end

  def changes_present?
    in_repo { !git_output("status", "--porcelain").empty? }
  end

  def commit_and_push
    in_repo do
      git!("add", "-A")
      git!("commit", "-m", build_commit_message)
      git!("push", "origin", @branch)
    end
  end

  def build_commit_message
    [
      "#{@commit_prefix}Benchmark results update - #{timestamp}".strip,
      "",
      metadata_lines
    ].flatten.compact.join("\n")
  end

  def timestamp
    Time.now.utc.strftime('%Y-%m-%d %H:%M UTC')
  end

  def metadata_lines
    return unless Dir.exist?(File.join(@source_dir, 'ruby-bench'))

    [
      ruby_versions_line,
      "Benchmarks: #{benchmark_count} result files"
    ].compact
  end

  def ruby_versions_line
    dates = ruby_version_dates
    "Ruby versions: #{dates.first}-#{dates.last}" if dates&.any?
  end

  def ruby_version_dates
    rubies_file = File.expand_path('../rubies.yml', __dir__)
    return unless File.exist?(rubies_file)

    YAML.load_file(rubies_file).keys.map(&:to_s).sort
  end

  def benchmark_count
    Dir.glob(File.join(@source_dir, 'ruby-bench', '*.yml')).size
  end

  # Git command helpers

  def git(*args, silent: false)
    opts = silent ? {out: File::NULL, err: File::NULL} : {}
    system("git", *args, **opts)
  end

  def git!(*args)
    system("git", *args, exception: true)
  end

  def git_output(*args)
    IO.popen(["git", *args], &:read).strip
  end

  def in_repo(&block)
    Dir.chdir(@local_path, &block)
  end

  def warn(message)
    $stderr.puts "WARNING: #{message}"
  end
end

ResultSyncer.new.sync!
