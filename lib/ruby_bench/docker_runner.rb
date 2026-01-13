# frozen_string_literal: true

class RubyBench
  class DockerRunner < Runner
    def initialize(rubies_path:)
      unless File.exist?(rubies_path)
        abort "ERROR: rubies.yml not found at #{rubies_path}. Please setup using bin/prepare-results.rb"
      end
      @rubies = YAML.load_file(rubies_path)
      @started_containers = []
      @current_container = nil
    end

    def next_target_date(existing_results)
      target_dates = @rubies.reject { |_, sha| sha.nil? }.keys.sort.reverse
      target_dates.find { |date| !existing_results.key?(date) }
    end

    def execute(benchmark, opts:, category:, no_pinning:)
      ensure_container_running(@current_target_date)
      env = "env BUNDLE_JOBS=8"
      category_arg = category ? "--category #{category}" : ""
      pinning_arg = no_pinning ? "--no-pinning" : ""
      timeout = 10 * 60
      cmd = [
        'docker', 'exec', @current_container, 'bash', '-c',
        "cd /rubybench/benchmark/ruby-bench && #{env} timeout --signal=KILL #{timeout} ./run_benchmarks.rb #{benchmark} #{category_arg} #{pinning_arg} -e 'ruby #{opts}'",
      ]
      IO.popen(cmd, &:read)
    end

    def setup_for_date(target_date)
      @current_target_date = target_date
    end

    def cleanup_after_benchmark
      return unless @current_container
      system('docker', 'exec', @current_container, 'git', 'config', '--global', '--add', 'safe.directory', '*', exception: true)
      system('docker', 'exec', @current_container, 'git', '-C', '/rubybench/benchmark/ruby-bench', 'clean', '-dfx', exception: true)
    end

    def shutdown
      @started_containers.each do |container|
        system('docker', 'rm', '-f', container, exception: true)
      end
    end

    private

    def ensure_container_running(target_date)
      container = "rubybench-#{target_date}"
      return if @current_container == container

      unless @started_containers.include?(container)
        system('docker', 'rm', '-f', container, exception: true, err: File::NULL)
        system(
          'docker', 'run', '-d', '--privileged', '--name', container,
          '-v', "#{Dir.pwd}:/rubybench",
          "ghcr.io/ruby/ruby:master-#{@rubies.fetch(target_date)}",
          'bash', '-c', 'while true; do sleep 100000; done',
          exception: true,
        )
        cmd = 'apt-get update && apt install -y build-essential curl git libsqlite3-dev libyaml-dev nodejs pkg-config sudo xz-utils'
        system('docker', 'exec', container, 'bash', '-c', cmd, exception: true)
        @started_containers << container
      end

      @current_container = container
    end
  end
end
