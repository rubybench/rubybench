# frozen_string_literal: true

require 'socket'

class RubyBench
  module Machine
    def self.arch
      `uname -m`.strip
    end

    def self.hostname
      Socket.gethostname.split('.').first.downcase.gsub(/[^a-z0-9-]/, '-')
    end

    def self.path
      "#{arch}/#{hostname}"
    end
  end
end
