#!/bin/bash
set -uxo pipefail # not using -e to minimize impact of bad benchmarks

rubybench=$(cd $(dirname "$0"); cd ..; pwd)
cd "$rubybench"

# Ruby ruby/ruby
for bench in benchmark/ruby/benchmark/*.rb benchmark/ruby/benchmark/*.yml; do
  bench="$(basename "$bench")"
  benchmark/ruby.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark ruby/ruby"

# Run yjit-bench
for bench in activerecord hexapdf liquid-render mail psych-load railsbench \
             binarytrees chunky_png erubi erubi_rails etanni fannkuchredux lee nbody optcarrot ruby-lsp rubykon; do
  benchmark/yjit-bench.rb "$bench"
done
bin/git-push.sh "ruby-kai1: Benchmark yjit-bench"
