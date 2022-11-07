#!/usr/bin/env ruby

# 1. Pick a not-too-old date when there's no result yet
# TODO: build a yaml file that lists available versions
date = 20221106

# 2. Run yjit-bench and capture the result
# TODO: use timeout
cmd = [
  'docker', 'run', '--privileged',
  '-v', "#{Dir.pwd}/yjit-bench:/yjit-bench",
  "rubylang/ruby:master-nightly-#{date}-focal",
  "bash", "-c",
  "cd /yjit-bench && ./run_benchmarks.rb optcarrot -e 'ruby --yjit'",
]
out = IO.popen(cmd, &:read)
puts out

# 3. Insert the result and Ruby description
# 4. git push
