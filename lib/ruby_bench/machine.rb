# frozen_string_literal: true

require 'socket'

class RubyBench
  module Machine
    LEGACY_MACHINES = %w[ruby-kai1].freeze

    def self.arch
      `uname -m`.strip
    end

    def self.hostname
      Socket.gethostname.split('.').first.downcase.gsub(/[^a-z0-9-]/, '-')
    end

    def self.path
      return nil if LEGACY_MACHINES.include?(hostname)
      "#{arch}/#{hostname}"
    end
  end
end
