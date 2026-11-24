# frozen_string_literal: true

require 'json'
require 'net/http'

class RubyBench
  class MMTkDockerRunner < DockerRunner
    DATE_WINDOW = 7

    private

    def candidate_dates
      super.first(DATE_WINDOW).select { |date| image_published?(@rubies.fetch(date)) }
    end

    def image_published?(sha)
      token = JSON.parse(Net::HTTP.get(URI('https://ghcr.io/token?scope=repository:ruby/ruby:pull'))).fetch('token')
      uri = URI("https://ghcr.io/v2/ruby/ruby/manifests/#{tag(sha)}")
      request = Net::HTTP::Head.new(uri, 'Authorization' => "Bearer #{token}", 'Accept' => 'application/vnd.oci.image.index.v1+json')
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }.is_a?(Net::HTTPSuccess)
    end

    def tag(sha)
      "master-modular-gc-#{sha}"
    end

    def image(target_date)
      "ghcr.io/ruby/ruby:#{tag(@rubies.fetch(target_date))}"
    end

    def container_name(target_date)
      "rubybench-mmtk-#{target_date}"
    end

    def ruby_command(opts)
      "env RUBY_GC_LIBRARY=mmtk ruby #{opts}"
    end
  end
end
