#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

# Run yjit-bench
benchmark/yjit-bench.rb
bin/dashboard.rb
bin/git-push.sh "ruby-kai1: Benchmark yjit-bench"

# Ruby ruby/ruby
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  benchmark/ruby.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark ruby/ruby"
