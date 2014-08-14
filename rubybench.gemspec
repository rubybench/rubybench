# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rubybench/version'

Gem::Specification.new do |spec|
  spec.name          = "rubybench"
  spec.version       = Rubybench::VERSION
  spec.authors       = ["y8"]
  spec.email         = ["info@rubyben.ch"]
  spec.summary       = %q{Like a rubyspec, but for benchmark}
  spec.description   = %q{Set of cases to measure ruby performance}
  spec.homepage      = "https://rubyben.ch/"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
end
